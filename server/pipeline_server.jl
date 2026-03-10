# ============================================================================
# PIPELINE AUTOMATION SERVER - TNSoftware Version
# ============================================================================
#
# Customized for TNSoftware project structure:
#   - HTML GUI in frontend/
#   - Data in data/
#   - Observables in data_obs/
#
# ============================================================================

using HTTP
using JSON
using Dates

# ============================================================================
# CONFIGURATION FROM start_server.jl
# ============================================================================

# Get configuration from start_server.jl globals
const DATA_DIR = isdefined(Main, :SERVER_DATA_DIR) ?
                 Main.SERVER_DATA_DIR :
                 joinpath(dirname(@__DIR__), "data")

const OBSERVABLES_DIR = isdefined(Main, :SERVER_OBSERVABLES_DIR) ?
                        Main.SERVER_OBSERVABLES_DIR :
                        joinpath(dirname(@__DIR__), "data_obs")

const FRONTEND_DIR = isdefined(Main, :SERVER_FRONTEND_DIR) ?
                     Main.SERVER_FRONTEND_DIR :
                     joinpath(dirname(@__DIR__), "frontend")

const REGISTRY_DIR = isdefined(Main, :SERVER_REGISTRY_DIR) ?
                     Main.SERVER_REGISTRY_DIR :
                     joinpath(dirname(@__DIR__), "registry")

println("Server configured with:")
println("  Data directory:        $DATA_DIR")
println("  Observables directory: $OBSERVABLES_DIR")
println("  Frontend directory:    $FRONTEND_DIR")
println("  Registry directory:    $REGISTRY_DIR")
println()

# Track active runs for progress updates
const ACTIVE_RUNS = Dict{String, Dict{String, Any}}()

# ============================================================================
# CORS Middleware (Allow browser requests)
# ============================================================================

function add_cors_headers(response::HTTP.Response)
    HTTP.setheader(response, "Access-Control-Allow-Origin" => "*")
    HTTP.setheader(response, "Access-Control-Allow-Methods" => "GET, POST, DELETE, OPTIONS")
    HTTP.setheader(response, "Access-Control-Allow-Headers" => "Content-Type")
    return response
end

# ============================================================================
# PROGRESS TRACKING
# ============================================================================

"""
Send progress update and log to console
"""
function send_progress(run_id::String, status::String, message::String, data::Dict=Dict())
    if haskey(ACTIVE_RUNS, run_id)
        ACTIVE_RUNS[run_id]["status"] = status
        ACTIVE_RUNS[run_id]["last_message"] = message
        ACTIVE_RUNS[run_id]["last_update"] = string(Dates.now())
        
        # Merge extra data
        if !isempty(data)
            for (k, v) in data
                ACTIVE_RUNS[run_id][k] = v
            end
        end
    end
    
    println("[$(Dates.format(Dates.now(), "HH:MM:SS"))] [$run_id] $status: $message")
end

# ============================================================================
# PIPELINE EXECUTION (Background Tasks)
# ============================================================================

"""
Execute simulation pipeline in background
"""
function execute_simulation_pipeline(config::Dict, mode::String, run_id::String)
    try
        send_progress(run_id, "running", "Starting simulation...")
        
        # Call your runner with absolute paths
        result, sim_run_id, sim_run_dir = run_simulation_from_config(
            config; 
            base_dir=DATA_DIR,
            force_rerun=false
        )
        
        if result === nothing
            # Deduplication - simulation already exists
            send_progress(run_id, "completed", "Simulation already completed (found existing run)", 
                         Dict("run_id" => sim_run_id, "run_dir" => sim_run_dir))
            ACTIVE_RUNS[run_id]["result"] = Dict(
                "status" => "completed",
                "type" => "simulation",
                "run_id" => sim_run_id,
                "run_dir" => sim_run_dir,
                "deduplicated" => true
            )
        else
            send_progress(run_id, "completed", "Simulation completed successfully",
                         Dict("run_id" => sim_run_id, "run_dir" => sim_run_dir))
            ACTIVE_RUNS[run_id]["result"] = Dict(
                "status" => "completed",
                "type" => "simulation",
                "run_id" => sim_run_id,
                "run_dir" => sim_run_dir,
                "deduplicated" => false
            )
        end
        
    catch e
        error_msg = sprint(showerror, e, catch_backtrace())
        println("\n" * "="^70)
        println("ERROR IN SIMULATION PIPELINE:")
        println("="^70)
        println(error_msg)
        println("="^70 * "\n")
        
        send_progress(run_id, "failed", "Simulation failed: $(sprint(showerror, e))")
        ACTIVE_RUNS[run_id]["result"] = Dict(
            "status" => "failed",
            "error" => error_msg
        )
    end
end

# ============================================================================
# HTTP HANDLERS
# ============================================================================

"""
POST /api/run
Run simulation pipeline
"""
function handle_run(req::HTTP.Request)
    try
        # Parse request body
        body = JSON.parse(String(req.body))
        config = body["config"]  # JSON config

        # Generate tracking ID
        tracking_id = string(Dates.format(Dates.now(), "yyyymmdd_HHMMSS"), "_", rand(1000:9999))

        # Initialize tracking
        ACTIVE_RUNS[tracking_id] = Dict(
            "mode" => "simulation",
            "status" => "queued",
            "start_time" => string(Dates.now()),
            "last_message" => "Pipeline queued",
            "last_update" => string(Dates.now())
        )

        println("\n" * "="^70)
        println("NEW PIPELINE REQUEST")
        println("="^70)
        println("Tracking ID: $tracking_id")
        println("Time: $(Dates.now())")
        println("="^70 * "\n")

        # Launch simulation pipeline in background
        @async execute_simulation_pipeline(config, "simulation", tracking_id)
        
        # Return tracking ID immediately
        response = Dict(
            "status" => "accepted",
            "tracking_id" => tracking_id,
            "message" => "Pipeline started in background"
        )
        
        return HTTP.Response(202, JSON.json(response))
        
    catch e
        error_response = Dict(
            "status" => "error",
            "message" => string(e)
        )
        return HTTP.Response(400, JSON.json(error_response))
    end
end

"""
GET /api/status/:tracking_id
Get current status of a run
"""
function handle_status(req::HTTP.Request)
    parts = split(req.target, '/')
    tracking_id = parts[end]
    
    if !haskey(ACTIVE_RUNS, tracking_id)
        return HTTP.Response(404, JSON.json(Dict("error" => "Run not found")))
    end
    
    return HTTP.Response(200, JSON.json(ACTIVE_RUNS[tracking_id]))
end

"""
GET /api/catalog
List all simulation runs
"""
function handle_catalog(req::HTTP.Request)
    try
        catalog = TNCodebase._load_catalog(base_dir=DATA_DIR)
        return HTTP.Response(200, JSON.json(catalog))
    catch e
        return HTTP.Response(500, JSON.json(Dict("error" => string(e))))
    end
end

"""
GET /api/active
List currently running pipelines
"""
function handle_active(req::HTTP.Request)
    active = Dict{String, Any}()
    for (id, info) in ACTIVE_RUNS
        if info["status"] in ["queued", "running"]
            active[id] = info
        end
    end
    return HTTP.Response(200, JSON.json(active))
end

"""
GET /
Serve HTML GUI from frontend/ directory
"""
function handle_root(req::HTTP.Request)
    html_path = joinpath(FRONTEND_DIR, "config_builder.html")

    if isfile(html_path)
        html_content = read(html_path, String)
        response = HTTP.Response(200, html_content)
        HTTP.setheader(response, "Content-Type" => "text/html")
        HTTP.setheader(response, "Cache-Control" => "no-cache, no-store, must-revalidate")
        return response
    else
        return HTTP.Response(404, """
            <h1>Config Builder Not Found</h1>
            <p>Expected location: $html_path</p>
            <p>Please make sure config_builder.html is in the frontend/ directory.</p>
        """)
    end
end

"""
GET /pipeline_automation.js
Serve JavaScript file from frontend/ directory
"""
function handle_js(req::HTTP.Request)
    js_path = joinpath(FRONTEND_DIR, "pipeline_automation.js")

    if isfile(js_path)
        js_content = read(js_path, String)
        response = HTTP.Response(200, js_content)
        HTTP.setheader(response, "Content-Type" => "application/javascript")
        HTTP.setheader(response, "Cache-Control" => "no-cache, no-store, must-revalidate")
        return response
    else
        return HTTP.Response(404, "// JavaScript file not found at: $js_path")
    end
end

# ============================================================================
# REGISTRY HANDLERS
# ============================================================================

"""
GET /api/registry/:name
Serve one of the four registry JSON files (models, systems, states, algorithms).
"""
function handle_registry_get(req::HTTP.Request)
    parts = split(req.target, '/')
    name = parts[end]  # last segment: models, systems, states, algorithms

    allowed = ["models", "systems", "states", "algorithms", "observables", "config_schema"]
    if !(name in allowed)
        return HTTP.Response(404, JSON.json(Dict(
            "error" => "Unknown registry: $name",
            "allowed" => allowed
        )))
    end

    path = joinpath(REGISTRY_DIR, "$(name).json")
    if !isfile(path)
        return HTTP.Response(404, JSON.json(Dict(
            "error" => "Registry file not found",
            "path"  => path
        )))
    end

    try
        content = read(path, String)
        response = HTTP.Response(200, content)
        HTTP.setheader(response, "Content-Type" => "application/json")
        return response
    catch e
        return HTTP.Response(500, JSON.json(Dict("error" => string(e))))
    end
end

"""
POST /api/registry/models
Register a new named user model.
Body: { "name", "display_name", "system_type", "backend" ("tn"|"ed"),
        "channels" (TN) or "terms" (ED), "description" (optional) }
"""
function handle_registry_post_models(req::HTTP.Request)
    try
        body = JSON.parse(String(req.body))

        for field in ["name", "display_name", "system_type", "backend"]
            if !haskey(body, field)
                return HTTP.Response(400, JSON.json(Dict(
                    "error" => "Missing required field: $field"
                )))
            end
        end

        backend = body["backend"]
        if !(backend in ["tn", "ed"])
            return HTTP.Response(400, JSON.json(Dict(
                "error" => "backend must be 'tn' or 'ed', got: $backend"
            )))
        end

        data_field = backend == "tn" ? "channels" : "terms"
        if !haskey(body, data_field)
            return HTTP.Response(400, JSON.json(Dict(
                "error" => "Missing '$data_field' for backend='$backend'"
            )))
        end

        path = joinpath(REGISTRY_DIR, "models.json")
        registry = JSON.parsefile(path)

        name = body["name"]
        if haskey(registry["user_models"]["models"], name)
            return HTTP.Response(409, JSON.json(Dict(
                "error" => "A user model named '$name' already exists. Choose a different name."
            )))
        end

        entry = Dict(
            "display_name"  => body["display_name"],
            "description"   => get(body, "description", ""),
            "system_type"   => body["system_type"],
            "backend"       => backend,
            "registered_at" => string(Dates.now()),
            data_field      => body[data_field]
        )

        registry["user_models"]["models"][name] = entry

        open(path, "w") do f
            JSON.print(f, registry, 2)
        end

        println("[Registry] Registered user model: $name ($(body["system_type"]), $backend)")

        response = HTTP.Response(201, JSON.json(Dict(
            "status"  => "created",
            "name"    => name,
            "message" => "Model '$name' registered successfully"
        )))
        HTTP.setheader(response, "Content-Type" => "application/json")
        return response

    catch e
        return HTTP.Response(500, JSON.json(Dict("error" => string(e))))
    end
end

"""
POST /api/registry/states
Register a new named user state. Appends to user_states.states in states.json.
Body: { "name": "...", "display_name": "...", "description": "...",
        "system_type": "spin"|"spinboson", "site_configs": [...],
        "boson_level": 0 }   ← boson_level only required for spinboson
"""
function handle_registry_post_states(req::HTTP.Request)
    try
        body = JSON.parse(String(req.body))

        for field in ["name", "display_name", "system_type", "site_configs"]
            if !haskey(body, field)
                return HTTP.Response(400, JSON.json(Dict(
                    "error" => "Missing required field: $field"
                )))
            end
        end

        path = joinpath(REGISTRY_DIR, "states.json")
        registry = JSON.parsefile(path)

        name = body["name"]
        if haskey(registry["user_states"]["states"], name)
            return HTTP.Response(409, JSON.json(Dict(
                "error" => "A user state named '$name' already exists. Choose a different name."
            )))
        end

        entry = Dict(
            "display_name"  => body["display_name"],
            "description"   => get(body, "description", ""),
            "system_type"   => body["system_type"],
            "registered_at" => string(Dates.now()),
            "site_configs"  => body["site_configs"]
        )
        if haskey(body, "boson_level")
            entry["boson_level"] = body["boson_level"]
        end

        registry["user_states"]["states"][name] = entry

        open(path, "w") do f
            JSON.print(f, registry, 2)
        end

        println("[Registry] Registered user state: $name ($(body["system_type"]))")

        response = HTTP.Response(201, JSON.json(Dict(
            "status"  => "created",
            "name"    => name,
            "message" => "State '$name' registered successfully"
        )))
        HTTP.setheader(response, "Content-Type" => "application/json")
        return response

    catch e
        return HTTP.Response(500, JSON.json(Dict("error" => string(e))))
    end
end

"""
DELETE /api/registry/models/:name
Remove a user model from models.json by key name.
"""
function handle_registry_delete_models(req::HTTP.Request)
    try
        parts = split(req.target, '/')
        name  = parts[end]

        path = joinpath(REGISTRY_DIR, "models.json")
        registry = JSON.parsefile(path)

        if !haskey(registry["user_models"]["models"], name)
            return HTTP.Response(404, JSON.json(Dict(
                "error" => "Model '$name' not found in user_models"
            )))
        end

        delete!(registry["user_models"]["models"], name)

        open(path, "w") do f
            JSON.print(f, registry, 2)
        end

        println("[Registry] Deleted user model: $name")

        response = HTTP.Response(200, JSON.json(Dict(
            "status"  => "deleted",
            "name"    => name,
            "message" => "Model '$name' deleted successfully"
        )))
        HTTP.setheader(response, "Content-Type" => "application/json")
        return response

    catch e
        return HTTP.Response(500, JSON.json(Dict("error" => string(e))))
    end
end

"""
DELETE /api/registry/states/:name
Remove a user state from states.json by key name.
"""
function handle_registry_delete_states(req::HTTP.Request)
    try
        parts = split(req.target, '/')
        name  = parts[end]

        path = joinpath(REGISTRY_DIR, "states.json")
        registry = JSON.parsefile(path)

        if !haskey(registry["user_states"]["states"], name)
            return HTTP.Response(404, JSON.json(Dict(
                "error" => "State '$name' not found in user_states"
            )))
        end

        delete!(registry["user_states"]["states"], name)

        open(path, "w") do f
            JSON.print(f, registry, 2)
        end

        println("[Registry] Deleted user state: $name")

        response = HTTP.Response(200, JSON.json(Dict(
            "status"  => "deleted",
            "name"    => name,
            "message" => "State '$name' deleted successfully"
        )))
        HTTP.setheader(response, "Content-Type" => "application/json")
        return response

    catch e
        return HTTP.Response(500, JSON.json(Dict("error" => string(e))))
    end
end

# ============================================================================
# QUERY HANDLERS
# ============================================================================

"""
    _parse_query_params(target) → Dict{Symbol, Any}

Parse URL query parameters from request target string.
Handles type conversion: numeric strings → numbers, "true"/"false" → bool.
"""
function _parse_query_params(target::String)
    params = Dict{Symbol, Any}()

    idx = findfirst('?', target)
    if idx === nothing
        return params
    end

    query_string = target[idx+1:end]
    if isempty(query_string)
        return params
    end

    for pair in split(query_string, '&')
        kv = split(pair, '=', limit=2)
        if length(kv) != 2
            continue
        end
        key = Symbol(HTTP.unescapeuri(kv[1]))
        val_str = HTTP.unescapeuri(kv[2])

        # Type conversion
        val = if val_str == "true"
            true
        elseif val_str == "false"
            false
        elseif all(c -> isdigit(c) || c == '-', val_str) && !isempty(val_str)
            parse(Int, val_str)
        elseif occursin(r"^-?\d+\.\d+$", val_str)
            parse(Float64, val_str)
        else
            val_str
        end

        params[key] = val
    end

    return params
end

"""
GET /api/catalog-info
Return catalog metadata for dynamic cascading filter dropdowns.
Calls _extract_catalog_info on the current catalog to get:
  algorithms (with their param values), models (with their param values),
  states_by_kind, core field values, N_values.
"""
function handle_catalog_info(req::HTTP.Request)
    try
        entries = TNCodebase._load_catalog(base_dir=DATA_DIR)
        info = TNCodebase._extract_catalog_info(entries)
        response = HTTP.Response(200, JSON.json(info))
        HTTP.setheader(response, "Content-Type" => "application/json")
        return response
    catch e
        return HTTP.Response(500, JSON.json(Dict("error" => sprint(showerror, e))))
    end
end

"""
GET /api/observable-catalog-info
Return observable catalog metadata for dynamic cascading filter dropdowns.
Calls _extract_observable_catalog_info on the current observable catalog to get:
  observable_types, sim_algorithms, sim_models, observable_params (per type),
  selection_types.
"""
function handle_observable_catalog_info(req::HTTP.Request)
    try
        entries = TNCodebase._load_observables_catalog(obs_base_dir=OBSERVABLES_DIR)
        info = TNCodebase._extract_observable_catalog_info(entries)
        response = HTTP.Response(200, JSON.json(info))
        HTTP.setheader(response, "Content-Type" => "application/json")
        return response
    catch e
        return HTTP.Response(500, JSON.json(Dict("error" => sprint(showerror, e))))
    end
end

"""
GET /api/query/simulations?algorithm=dmrg&N_gte=10&...
Query simulation catalog with URL query parameters.
"""
function handle_query_simulations(req::HTTP.Request)
    try
        params = _parse_query_params(req.target)

        # Extract base_dir if provided, otherwise use default
        base_dir = pop!(params, :base_dir, DATA_DIR)

        results = query_catalog(; base_dir=string(base_dir), params...)

        # Strip _query_type metadata if present
        clean = [Dict(k => v for (k, v) in r if k != "_query_type") for r in results]

        response_data = Dict(
            "count" => length(clean),
            "results" => clean
        )

        response = HTTP.Response(200, JSON.json(response_data))
        HTTP.setheader(response, "Content-Type" => "application/json")
        return response
    catch e
        return HTTP.Response(500, JSON.json(Dict("error" => sprint(showerror, e))))
    end
end

"""
GET /api/query/observables?observable_type=correlation_function&sim_algorithm=dmrg&...
Query observable catalog with URL query parameters.
"""
function handle_query_observables(req::HTTP.Request)
    try
        params = _parse_query_params(req.target)

        # Extract obs_base_dir if provided, otherwise use default
        obs_base_dir = pop!(params, :obs_base_dir, OBSERVABLES_DIR)

        results = query_observables(; obs_base_dir=string(obs_base_dir), params...)

        # Strip _query_type metadata if present
        clean = [Dict(k => v for (k, v) in r if k != "_query_type") for r in results]

        response_data = Dict(
            "count" => length(clean),
            "results" => clean
        )

        response = HTTP.Response(200, JSON.json(response_data))
        HTTP.setheader(response, "Content-Type" => "application/json")
        return response
    catch e
        return HTTP.Response(500, JSON.json(Dict("error" => sprint(showerror, e))))
    end
end

# ============================================================================
# RESULTS HANDLERS
# ============================================================================

"""
GET /api/results/simulations/:run_id
Return simulation metadata and config for a given run_id.
Looks up the run in the catalog and returns its full entry + config.
"""
function handle_results_simulation(req::HTTP.Request)
    try
        parts = split(req.target, '/')
        run_id = parts[end]

        # Query catalog for this specific run_id
        results = query_catalog(; base_dir=DATA_DIR, run_id=run_id)

        if isempty(results)
            return HTTP.Response(404, JSON.json(Dict("error" => "Simulation run not found: $run_id")))
        end

        entry = results[1]
        run_dir = entry["run_dir"]

        # Load config.json if available
        config_path = joinpath(run_dir, "config.json")
        config = isfile(config_path) ? JSON.parsefile(config_path) : nothing

        # Load metadata.json if available
        metadata_path = joinpath(run_dir, "metadata.json")
        metadata = isfile(metadata_path) ? JSON.parsefile(metadata_path) : nothing

        response_data = Dict(
            "run_id" => run_id,
            "run_dir" => run_dir,
            "catalog_entry" => Dict(k => v for (k, v) in entry if k != "_query_type"),
            "config" => config,
            "metadata" => metadata
        )

        response = HTTP.Response(200, JSON.json(response_data))
        HTTP.setheader(response, "Content-Type" => "application/json")
        return response
    catch e
        return HTTP.Response(500, JSON.json(Dict("error" => sprint(showerror, e))))
    end
end

"""
GET /api/results/observables/:obs_run_id
Return observable results as JSON-serializable data.
Loads all computed sweep values from JLD2 and returns them.
"""
function handle_results_observable(req::HTTP.Request)
    try
        parts = split(req.target, '/')
        obs_run_id = parts[end]

        # Query observable catalog to find this run
        results = query_observables(; obs_base_dir=OBSERVABLES_DIR, obs_run_id=obs_run_id)

        if isempty(results)
            return HTTP.Response(404, JSON.json(Dict("error" => "Observable run not found: $obs_run_id")))
        end

        entry = results[1]
        obs_run_dir = entry["obs_run_dir"]

        # Load metadata
        metadata_path = joinpath(obs_run_dir, "metadata.json")
        if !isfile(metadata_path)
            return HTTP.Response(404, JSON.json(Dict("error" => "Observable metadata not found at $obs_run_dir")))
        end
        metadata = JSON.parsefile(metadata_path)

        # Load all observable values using the timeseries loader
        timeseries = load_observable_timeseries(obs_run_dir)

        # Convert values to JSON-safe format (handle complex numbers, matrices, etc.)
        json_values = []
        for v in timeseries["values"]
            if v isa AbstractMatrix
                push!(json_values, [collect(row) for row in eachrow(v)])
            elseif v isa AbstractVector
                push!(json_values, collect(v))
            elseif v isa Complex
                push!(json_values, Dict("real" => real(v), "imag" => imag(v)))
            else
                push!(json_values, v)
            end
        end

        response_data = Dict(
            "obs_run_id" => obs_run_id,
            "obs_run_dir" => obs_run_dir,
            "catalog_entry" => Dict(k => v for (k, v) in entry if k != "_query_type"),
            "metadata" => metadata,
            "data" => Dict(
                "indices" => timeseries["indices"],
                "values" => json_values
            )
        )

        if haskey(timeseries, "times")
            response_data["data"]["times"] = timeseries["times"]
        end
        if haskey(timeseries, "energies")
            response_data["data"]["energies"] = timeseries["energies"]
        end

        response = HTTP.Response(200, JSON.json(response_data))
        HTTP.setheader(response, "Content-Type" => "application/json")
        return response
    catch e
        return HTTP.Response(500, JSON.json(Dict("error" => sprint(showerror, e))))
    end
end

# ============================================================================
# OBSERVABLE CALCULATE HANDLER
# ============================================================================

"""
POST /api/observables/calculate
Calculate observable on existing simulation data using run_id.

Body:
{
  "run_id": "20241103_142530_a3f5b2c1",
  "observable": {
    "type": "correlation_function",
    "params": { "site_i": 1, "site_j": 10, "operator": "Z" }
  },
  "selection": {
    "type": "all"
  }
}
"""
function handle_observable_calculate(req::HTTP.Request)
    try
        body = JSON.parse(String(req.body))

        # Validate required fields
        for field in ["run_id", "observable"]
            if !haskey(body, field)
                return HTTP.Response(400, JSON.json(Dict(
                    "error" => "Missing required field: $field"
                )))
            end
        end

        run_id = body["run_id"]
        observable_config = body["observable"]
        selection_config = get(body, "selection", Dict("selection" => "all"))

        # Normalize selection format
        if !haskey(selection_config, "selection") && haskey(selection_config, "type")
            selection_config["selection"] = pop!(selection_config, "type")
        elseif !haskey(selection_config, "selection")
            selection_config["selection"] = "all"
        end

        # Generate tracking ID
        tracking_id = string(Dates.format(Dates.now(), "yyyymmdd_HHMMSS"), "_obs_", rand(1000:9999))

        ACTIVE_RUNS[tracking_id] = Dict(
            "mode" => "observable_calculate",
            "status" => "queued",
            "start_time" => string(Dates.now()),
            "last_message" => "Observable calculation queued",
            "last_update" => string(Dates.now()),
            "sim_run_id" => run_id
        )

        println("\n" * "="^70)
        println("NEW OBSERVABLE CALCULATION REQUEST")
        println("="^70)
        println("Tracking ID: $tracking_id")
        println("Simulation run_id: $run_id")
        println("Observable: $(observable_config["type"])")
        println("="^70 * "\n")

        # Launch calculation in background
        @async begin
            try
                send_progress(tracking_id, "running", "Starting observable calculation...")

                obs_run_id, obs_run_dir = run_observable_from_run_id(
                    run_id,
                    observable_config,
                    selection_config;
                    base_dir=DATA_DIR,
                    obs_base_dir=OBSERVABLES_DIR
                )

                send_progress(tracking_id, "completed", "Observable calculation completed",
                             Dict("obs_run_id" => obs_run_id, "obs_run_dir" => obs_run_dir))
                ACTIVE_RUNS[tracking_id]["result"] = Dict(
                    "status" => "completed",
                    "type" => "observable",
                    "obs_run_id" => obs_run_id,
                    "obs_run_dir" => obs_run_dir,
                    "sim_run_id" => run_id
                )
            catch e
                error_msg = sprint(showerror, e, catch_backtrace())
                send_progress(tracking_id, "failed", "Observable calculation failed: $(sprint(showerror, e))")
                ACTIVE_RUNS[tracking_id]["result"] = Dict(
                    "status" => "failed",
                    "error" => error_msg
                )
            end
        end

        response = Dict(
            "status" => "accepted",
            "tracking_id" => tracking_id,
            "message" => "Observable calculation started in background"
        )

        return HTTP.Response(202, JSON.json(response))

    catch e
        return HTTP.Response(400, JSON.json(Dict("error" => sprint(showerror, e))))
    end
end

# ============================================================================
# ROUTER
# ============================================================================

function route_request(req::HTTP.Request)
    path = req.target
    
    # CORS preflight
    if req.method == "OPTIONS"
        response = HTTP.Response(200)
        return add_cors_headers(response)
    end
    
    # Strip query string for route matching
    route_path = split(path, '?')[1]

    # Route to handlers
    response = if req.method == "POST" && startswith(route_path, "/api/run")
        handle_run(req)
    elseif req.method == "GET" && startswith(route_path, "/api/status/")
        handle_status(req)
    elseif req.method == "GET" && route_path == "/api/catalog"
        handle_catalog(req)
    elseif req.method == "GET" && route_path == "/api/active"
        handle_active(req)

    # Catalog info endpoints (metadata for dynamic filter dropdowns)
    elseif req.method == "GET" && route_path == "/api/catalog-info"
        handle_catalog_info(req)
    elseif req.method == "GET" && route_path == "/api/observable-catalog-info"
        handle_observable_catalog_info(req)

    # Query endpoints
    elseif req.method == "GET" && startswith(route_path, "/api/query/simulations")
        handle_query_simulations(req)
    elseif req.method == "GET" && startswith(route_path, "/api/query/observables")
        handle_query_observables(req)

    # Results endpoints
    elseif req.method == "GET" && startswith(route_path, "/api/results/observables/")
        handle_results_observable(req)
    elseif req.method == "GET" && startswith(route_path, "/api/results/simulations/")
        handle_results_simulation(req)

    # Observable calculate endpoint
    elseif req.method == "POST" && route_path == "/api/observables/calculate"
        handle_observable_calculate(req)

    # Registry endpoints
    elseif req.method == "POST" && route_path == "/api/registry/models"
        handle_registry_post_models(req)
    elseif req.method == "POST" && route_path == "/api/registry/states"
        handle_registry_post_states(req)
    elseif req.method == "DELETE" && startswith(route_path, "/api/registry/models/")
        handle_registry_delete_models(req)
    elseif req.method == "DELETE" && startswith(route_path, "/api/registry/states/")
        handle_registry_delete_states(req)
    elseif req.method == "GET" && startswith(route_path, "/api/registry/")
        handle_registry_get(req)

    # Static files
    elseif req.method == "GET" && route_path == "/pipeline_automation.js"
        handle_js(req)
    elseif req.method == "GET" && route_path == "/"
        handle_root(req)
    else
        HTTP.Response(404, "Not Found: $path")
    end
    
    return add_cors_headers(response)
end

# ============================================================================
# SERVER STARTUP
# ============================================================================

function start_server(port::Int=8080, host::String="127.0.0.1")
    println("="^70)
    println("PIPELINE AUTOMATION SERVER - TNSoftware")
    println("="^70)
    println("Starting server on http://$host:$port")
    println()
    println("Endpoints:")
    println("  POST   /api/run                          - Run simulation pipeline")
    println("  GET    /api/status/:id                   - Check pipeline status")
    println("  GET    /api/catalog                      - List all simulation runs")
    println("  GET    /api/active                       - List running pipelines")
    println()
    println("  GET    /api/query/simulations?...        - Query simulation catalog")
    println("  GET    /api/query/observables?...        - Query observable catalog")
    println("  GET    /api/results/simulations/:run_id  - Get simulation results & metadata")
    println("  GET    /api/results/observables/:run_id  - Get observable results as JSON")
    println("  POST   /api/observables/calculate        - Calculate observable on existing data")
    println()
    println("  GET    /api/registry/:name               - Get registry (models/systems/states/algorithms/observables)")
    println("  POST   /api/registry/models              - Register a user model")
    println("  POST   /api/registry/states              - Register a user state")
    println("  DELETE /api/registry/models/:name        - Delete a user model")
    println("  DELETE /api/registry/states/:name        - Delete a user state")
    println()
    println("  GET    /                                 - Web interface")
    println("  GET    /pipeline_automation.js           - JavaScript")
    println()
    println("Open http://$host:$port in your browser to use the GUI")
    println()
    println("Press Ctrl+C to stop server")
    println("="^70)
    println()
    
    try
        HTTP.serve(route_request, host, port)
    catch e
        if isa(e, InterruptException)
            println("\n" * "="^70)
            println("Server stopped by user")
            println("="^70)
        else
            println("Server error: $e")
            rethrow(e)
        end
    end
end

# Export for use
export start_server