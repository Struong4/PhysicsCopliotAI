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

"""
Execute full analysis pipeline (simulation + observables) in background
"""
function execute_analysis_pipeline(config::Dict, mode::String, run_id::String)
    try
        send_progress(run_id, "running", "Starting analysis pipeline...")
        
        # Call your runner with absolute paths
        obs_run_id, obs_run_dir = run_observable_calculation_from_config(
            config;
            base_dir=DATA_DIR,                    # Simulation data location
            obs_base_dir=OBSERVABLES_DIR,         # Observable data location (data_obs)
            force_rerun=false
        )
        
        if obs_run_id === nothing
            # Deduplication - observable already calculated
            send_progress(run_id, "completed", "Observable already calculated (found existing run)",
                         Dict("obs_run_dir" => obs_run_dir))
            ACTIVE_RUNS[run_id]["result"] = Dict(
                "status" => "completed",
                "type" => "analysis",
                "obs_run_id" => obs_run_id,
                "obs_run_dir" => obs_run_dir,
                "deduplicated" => true
            )
        else
            send_progress(run_id, "completed", "Analysis pipeline completed successfully",
                         Dict("obs_run_id" => obs_run_id, "obs_run_dir" => obs_run_dir))
            ACTIVE_RUNS[run_id]["result"] = Dict(
                "status" => "completed",
                "type" => "analysis",
                "obs_run_id" => obs_run_id,
                "obs_run_dir" => obs_run_dir,
                "deduplicated" => false
            )
        end
        
    catch e
        error_msg = sprint(showerror, e, catch_backtrace())
        println("\n" * "="^70)
        println("ERROR IN ANALYSIS PIPELINE:")
        println("="^70)
        println(error_msg)
        println("="^70 * "\n")
        
        send_progress(run_id, "failed", "Analysis failed: $(sprint(showerror, e))")
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
Run simulation or analysis pipeline
"""
function handle_run(req::HTTP.Request)
    try
        # Parse request body
        body = JSON.parse(String(req.body))
        mode = body["mode"]      # "simulation" or "analysis"
        config = body["config"]  # JSON config
        
        # Generate tracking ID
        tracking_id = string(Dates.format(Dates.now(), "yyyymmdd_HHMMSS"), "_", rand(1000:9999))
        
        # Initialize tracking
        ACTIVE_RUNS[tracking_id] = Dict(
            "mode" => mode,
            "status" => "queued",
            "start_time" => string(Dates.now()),
            "last_message" => "Pipeline queued",
            "last_update" => string(Dates.now())
        )
        
        println("\n" * "="^70)
        println("NEW PIPELINE REQUEST")
        println("="^70)
        println("Tracking ID: $tracking_id")
        println("Mode: $mode")
        println("Time: $(Dates.now())")
        println("="^70 * "\n")
        
        # Launch pipeline in background
        if mode == "simulation"
            @async execute_simulation_pipeline(config, mode, tracking_id)
        else # mode == "analysis"
            @async execute_analysis_pipeline(config, mode, tracking_id)
        end
        
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
        catalog = _load_catalog(base_dir=DATA_DIR)
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

    allowed = ["models", "systems", "states", "algorithms"]
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
# ROUTER
# ============================================================================

function route_request(req::HTTP.Request)
    path = req.target
    
    # CORS preflight
    if req.method == "OPTIONS"
        response = HTTP.Response(200)
        return add_cors_headers(response)
    end
    
    # Route to handlers
    response = if req.method == "POST" && startswith(path, "/api/run")
        handle_run(req)
    elseif req.method == "GET" && startswith(path, "/api/status/")
        handle_status(req)
    elseif req.method == "GET" && path == "/api/catalog"
        handle_catalog(req)
    elseif req.method == "GET" && path == "/api/active"
        handle_active(req)
    elseif req.method == "POST" && path == "/api/registry/models"
        handle_registry_post_models(req)
    elseif req.method == "POST" && path == "/api/registry/states"
        handle_registry_post_states(req)
    elseif req.method == "DELETE" && startswith(path, "/api/registry/models/")
        handle_registry_delete_models(req)
    elseif req.method == "DELETE" && startswith(path, "/api/registry/states/")
        handle_registry_delete_states(req)
    elseif req.method == "GET" && startswith(path, "/api/registry/")
        handle_registry_get(req)
    elseif req.method == "GET" && path == "/pipeline_automation.js"
        handle_js(req)
    elseif req.method == "GET" && path == "/"
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
    println("  POST   /api/run                    - Run pipeline")
    println("  GET    /api/status/:id             - Check status")
    println("  GET    /api/catalog                - List all runs")
    println("  GET    /api/active                 - List running pipelines")
    println("  GET    /api/registry/:name         - Get registry (models/systems/states/algorithms)")
    println("  POST   /api/registry/models        - Register a user model")
    println("  POST   /api/registry/states        - Register a user state")
    println("  DELETE /api/registry/models/:name  - Delete a user model")
    println("  DELETE /api/registry/states/:name  - Delete a user state")
    println("  GET    /                           - Web interface")
    println("  GET    /pipeline_automation.js     - JavaScript")
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