# ============================================================================
# QUERY INTERFACE FOR OBSERVABLE CATALOG (TN + ED)
# ============================================================================
#
# This module provides query functionality for discovering observable calculations.
# Operates exclusively on observables_catalog.jsonl - no file system scanning.
#
# USAGE:
#   results = query_observables(observable_type="correlation_function")
#   results = query_observables(sim_algorithm="ed_spectrum", model_name="long_range_ising")
#   display_observable_results(results)
#
# FILTER NAMING CONVENTION:
#   - Top-level: obs_run_id, sim_run_id, status
#   - Simulation: sim_algorithm, sim_system_type, sim_N, sim_model_name, sim_model_<param>
#   - Observable: observable_type, observable_<param>
#   - Analysis: analysis_selection_type, analysis_<param>
#   - Results: result_<field>
#
# ============================================================================

using JSON
using Dates
using Printf

# ============================================================================
# PART 1: QUERY FUNCTION
# ============================================================================

"""
    query_observables(; obs_base_dir="observables", filters...) -> Vector{Dict}

Query the observable catalog for calculations matching specified filters.

# Filter Syntax
- Top-level: `obs_run_id`, `sim_run_id`, `status`
- Simulation: `sim_algorithm`, `sim_system_type`, `sim_N`, `sim_model_name`, `sim_model_<param>`
- Observable: `observable_type`, `observable_<param>` (e.g., `observable_operator`, `observable_site`)
- Analysis: `analysis_selection_type`, `analysis_<param>`
- Results: `result_<field>` (e.g., `result_items_processed`)

# Comparison Operators
Append suffix to field name:
- `_gt`: greater than
- `_gte`: greater than or equal
- `_lt`: less than
- `_lte`: less than or equal

# Returns
Vector of matching catalog entries with computed `obs_run_dir` path.

# Examples
```julia
# Find all correlation function calculations
results = query_observables(observable_type="correlation_function")

# Find observables from ED spectrum runs
results = query_observables(sim_algorithm="ed_spectrum")

# Find observables on specific model
results = query_observables(
    sim_model_name="long_range_ising",
    observable_type="entanglement_entropy"
)

# Find observables with specific operator
results = query_observables(observable_operator="Z")

# Find observables for specific simulation
results = query_observables(sim_run_id="20241104_153045_a3f5b2c1")
```
"""
function query_observables(; obs_base_dir::String="observables", filters...)

    obs_base_dir = abspath(obs_base_dir)

    entries = _load_observables_catalog(obs_base_dir=obs_base_dir)
    
    if isempty(entries)
        println("Observables catalog is empty.")
        return Dict{String, Any}[]
    end
    
    results = Dict{String, Any}[]
    
    for entry in entries
        if _matches_observable_filters(entry, filters)
            entry_with_path = copy(entry)
            entry_with_path["obs_run_dir"] = _compute_obs_run_dir(entry, obs_base_dir)
            push!(results, entry_with_path)
        end
    end
    
    return results
end

# ============================================================================
# PART 2: FILTER MATCHING
# ============================================================================

function _matches_observable_filters(entry::Dict, filters)
    for (key, value) in filters
        if !_matches_single_observable_filter(entry, key, value)
            return false
        end
    end
    return true
end

function _matches_single_observable_filter(entry::Dict, key::Symbol, value)
    key_str = String(key)
    op, field_name = _parse_observable_filter_key(key_str)
    field_value = _get_observable_field_value(entry, field_name)
    
    if field_value === nothing
        return false
    end
    
    return _compare_observable(field_value, op, value)
end

function _parse_observable_filter_key(key::String)
    if endswith(key, "_gte")
        return (:gte, key[1:end-4])
    elseif endswith(key, "_lte")
        return (:lte, key[1:end-4])
    elseif endswith(key, "_gt")
        return (:gt, key[1:end-3])
    elseif endswith(key, "_lt")
        return (:lt, key[1:end-3])
    else
        return (:eq, key)
    end
end

"""
    _get_observable_field_value(entry, field_name) -> value or nothing

Extract field value from nested observable entry structure.

Field name patterns:
- "status" -> entry["status"]
- "sim_algorithm" -> entry["simulation"]["core"]["algorithm"]
- "sim_N" -> entry["simulation"]["core"]["N"]
- "sim_model_name" -> entry["simulation"]["model"]["name"]
- "sim_model_J" -> entry["simulation"]["model"]["params"]["J"]
- "observable_type" -> entry["observable"]["type"]
- "observable_operator" -> entry["observable"]["params"]["operator"]
- "analysis_selection_type" -> entry["analysis_params"]["sweep_selection"]["type"]
- "result_items_processed" -> entry["results_summary"]["items_processed"]
"""
function _get_observable_field_value(entry::Dict, field_name::String)
    # Top-level fields
    if field_name in ["obs_run_id", "sim_run_id", "config_hash", "timestamp", "status"]
        return get(entry, field_name, nothing)
    end
    
    # Simulation info fields (with sim_ prefix)
    if startswith(field_name, "sim_")
        return _get_sim_info_field(entry, field_name[5:end])
    end
    
    # Observable fields (with observable_ prefix)
    if startswith(field_name, "observable_")
        return _get_observable_field(entry, field_name[12:end])
    end
    
    # Analysis fields (with analysis_ prefix)
    if startswith(field_name, "analysis_")
        return _get_analysis_field(entry, field_name[10:end])
    end
    
    # Results summary (with result_ prefix)
    if startswith(field_name, "result_")
        result_field = field_name[8:end]
        return get(get(entry, "results_summary", Dict()), result_field, nothing)
    end
    
    return nothing
end

function _get_sim_info_field(entry::Dict, field_name::String)
    sim = get(entry, "simulation", nothing)
    if sim === nothing
        return nothing
    end
    
    # Core fields
    if field_name == "algorithm"
        core = get(sim, "core", nothing)
        return core === nothing ? nothing : get(core, "algorithm", nothing)
    elseif field_name in ["system_type", "N", "N_spins", "nmax", "S", "dtype"]
        core = get(sim, "core", nothing)
        return core === nothing ? nothing : get(core, field_name, nothing)
    end
    
    # Algorithm params
    if field_name in ["solver", "chi_max", "cutoff", "dt", "n_sweeps", "n_states", "n_steps", "use_sparse"]
        algo_params = get(sim, "algorithm_params", nothing)
        return algo_params === nothing ? nothing : get(algo_params, field_name, nothing)
    end
    
    # Model name
    if field_name == "model_name"
        model = get(sim, "model", nothing)
        return model === nothing ? nothing : get(model, "name", nothing)
    end
    
    # Model kind
    if field_name == "model_kind"
        model = get(sim, "model", nothing)
        return model === nothing ? nothing : get(model, "kind", nothing)
    end
    
    # Model params (with model_ prefix)
    if startswith(field_name, "model_")
        model_param = field_name[7:end]
        model = get(sim, "model", nothing)
        if model !== nothing
            params = get(model, "params", nothing)
            if params !== nothing
                return get(params, model_param, nothing)
            end
        end
    end
    
    # State name
    if field_name == "state_name"
        state = get(sim, "state", nothing)
        return state === nothing ? nothing : get(state, "name", nothing)
    end
    
    # State kind
    if field_name == "state_kind"
        state = get(sim, "state", nothing)
        return state === nothing ? nothing : get(state, "kind", nothing)
    end
    
    return nothing
end

function _get_observable_field(entry::Dict, field_name::String)
    obs = get(entry, "observable", nothing)
    if obs === nothing
        return nothing
    end
    
    # Direct observable field
    if field_name == "type"
        return get(obs, "type", nothing)
    end
    
    # Observable params
    params = get(obs, "params", nothing)
    if params !== nothing
        return get(params, field_name, nothing)
    end
    
    return nothing
end

function _get_analysis_field(entry::Dict, field_name::String)
    analysis_params = get(entry, "analysis_params", nothing)
    if analysis_params === nothing
        return nothing
    end
    
    # Check in sweep_selection, step_selection, or state_selection
    for selection_key in ["sweep_selection", "step_selection", "state_selection"]
        if haskey(analysis_params, selection_key)
            selection = analysis_params[selection_key]
            # Check if asking for the type
            if field_name == "selection_type"
                return get(selection, "type", nothing)
            end
            # Check for other fields in selection
            if haskey(selection, field_name)
                return selection[field_name]
            end
        end
    end
    
    return nothing
end

function _compare_observable(field_value, op::Symbol, filter_value)
    if op == :eq
        return field_value == filter_value
    elseif op == :gt
        return field_value > filter_value
    elseif op == :gte
        return field_value >= filter_value
    elseif op == :lt
        return field_value < filter_value
    elseif op == :lte
        return field_value <= filter_value
    else
        error("Unknown comparison operator: $op")
    end
end

# ============================================================================
# PART 3: PATH COMPUTATION
# ============================================================================

function _compute_obs_run_dir(entry::Dict, obs_base_dir::String)

    obs_base_dir = abspath(obs_base_dir)

    algorithm = entry["simulation"]["core"]["algorithm"]
    sim_run_id = entry["sim_run_id"]
    obs_run_id = entry["obs_run_id"]
    return joinpath(obs_base_dir, algorithm, sim_run_id, obs_run_id)
end

# ============================================================================
# PART 4: DISPLAY FUNCTIONS
# ============================================================================

function display_observable_results(results::Vector{Dict{String, Any}}; max_rows::Int=20)
    if isempty(results)
        println("No matching observable calculations found.")
        return
    end
    
    n_results = length(results)
    println("\n", "="^80)
    println("Found $n_results matching observable calculation(s)")
    println("="^80)
    
    display_count = min(n_results, max_rows)
    
    for (i, entry) in enumerate(results[1:display_count])
        _display_single_observable_result(entry, i)
    end
    
    if n_results > max_rows
        println("\n... and $(n_results - max_rows) more results")
    end
    
    println("="^80)
end

function _display_single_observable_result(entry::Dict, index::Int)
    println("\n[$index] $(entry["obs_run_id"])")
    println("    Status: $(entry["status"])")
    println("    Simulation: $(entry["sim_run_id"])")
    
    sim = entry["simulation"]
    core = sim["core"]
    model = sim["model"]
    println("    Algorithm: $(core["algorithm"]) | Model: $(model["name"]) | N: $(get(core, "N", get(core, "N_spins", "?")))")
    
    obs = entry["observable"]
    print("    Observable: $(obs["type"])")
    if haskey(obs, "params") && !isempty(obs["params"])
        params_str = join(["$k=$v" for (k, v) in obs["params"]], ", ")
        print(" ($params_str)")
    end
    println()
    
    # Determine selection type from analysis_params
    analysis_params = entry["analysis_params"]
    selection_type = "unknown"
    if haskey(analysis_params, "sweep_selection")
        selection_type = analysis_params["sweep_selection"]["type"]
    elseif haskey(analysis_params, "step_selection")
        selection_type = analysis_params["step_selection"]["type"]
    elseif haskey(analysis_params, "state_selection")
        selection_type = analysis_params["state_selection"]["type"]
    end
    println("    Selection: $selection_type")
    
    if haskey(entry, "results_summary") && !isempty(entry["results_summary"])
        summary_str = join(["$k=$v" for (k, v) in entry["results_summary"]], ", ")
        println("    Results: $summary_str")
    end
    
    println("    Path: $(entry["obs_run_dir"])")
end

function display_observable_results_compact(results::Vector{Dict{String, Any}})
    if isempty(results)
        println("No matching observable calculations found.")
        return
    end
    
    println("\n", "-"^120)
    @printf("%-28s %-10s %-28s %-25s %-15s\n", 
            "obs_run_id", "status", "sim_run_id", "observable_type", "selection")
    println("-"^120)
    
    for entry in results
        obs_run_id = entry["obs_run_id"]
        status = entry["status"]
        sim_run_id = entry["sim_run_id"]
        obs_type = entry["observable"]["type"]
        selection = entry["analysis"]["selection_type"]
        
        @printf("%-28s %-10s %-28s %-25s %-15s\n",
                obs_run_id, status, sim_run_id, obs_type, selection)
    end
    
    println("-"^120)
    println("Total: $(length(results)) observable calculation(s)")
end

# ============================================================================
# PART 5: CONVENIENCE FUNCTIONS
# ============================================================================

function get_observable_run_ids(results::Vector{Dict{String, Any}})
    return [r["obs_run_id"] for r in results]
end

function get_observable_run_dirs(results::Vector{Dict{String, Any}})
    return [r["obs_run_dir"] for r in results]
end

function load_observable_config(result::Dict; obs_base_dir::String="observables")

    obs_base_dir = abspath(obs_base_dir)

    obs_run_dir = get(result, "obs_run_dir", nothing)
    
    if obs_run_dir === nothing
        obs_run_dir = _compute_obs_run_dir(result, obs_base_dir)
    end
    
    config_path = joinpath(obs_run_dir, "observable_config.json")
    
    if !isfile(config_path)
        error("Observable config file not found: $config_path")
    end
    
    return JSON.parsefile(config_path)
end

function list_observable_types(; obs_base_dir::String="observables")

    obs_base_dir = abspath(obs_base_dir)

    entries = _load_observables_catalog(obs_base_dir=obs_base_dir)
    types = Set{String}()
    for entry in entries
        push!(types, entry["observable"]["type"])
    end
    return sort(collect(types))
end

function list_observable_algorithms(; obs_base_dir::String="observables")

    obs_base_dir = abspath(obs_base_dir)

    entries = _load_observables_catalog(obs_base_dir=obs_base_dir)
    algorithms = Set{String}()
    for entry in entries
        push!(algorithms, entry["simulation"]["core"]["algorithm"])
    end
    return sort(collect(algorithms))
end

function observables_catalog_summary(; obs_base_dir::String="observables")

    obs_base_dir = abspath(obs_base_dir)

    entries = _load_observables_catalog(obs_base_dir=obs_base_dir)
    
    if isempty(entries)
        println("Observables catalog is empty.")
        return
    end
    
    status_counts = Dict{String, Int}()
    algo_counts = Dict{String, Int}()
    obs_type_counts = Dict{String, Int}()
    
    for entry in entries
        status = entry["status"]
        algo = entry["simulation"]["core"]["algorithm"]
        obs_type = entry["observable"]["type"]
        
        status_counts[status] = get(status_counts, status, 0) + 1
        algo_counts[algo] = get(algo_counts, algo, 0) + 1
        obs_type_counts[obs_type] = get(obs_type_counts, obs_type, 0) + 1
    end
    
    println("\n", "="^60)
    println("OBSERVABLES CATALOG SUMMARY")
    println("="^60)
    println("Total calculations: $(length(entries))")
    
    println("\nBy status:")
    for (status, count) in sort(collect(status_counts))
        println("  $status: $count")
    end
    
    println("\nBy simulation algorithm:")
    for (algo, count) in sort(collect(algo_counts))
        println("  $algo: $count")
    end
    
    println("\nBy observable type:")
    for (obs_type, count) in sort(collect(obs_type_counts))
        println("  $obs_type: $count")
    end
    
    println("="^60)
end

"""
    get_observables_for_simulation(sim_run_id; obs_base_dir="observables") -> Vector{Dict}

Get all observable calculations for a specific simulation run.
"""
function get_observables_for_simulation(sim_run_id::String; obs_base_dir::String="observables")

    obs_base_dir = abspath(obs_base_dir)

    return query_observables(sim_run_id=sim_run_id, obs_base_dir=obs_base_dir)
end

"""
    compare_observables_across_algorithms(observable_type, model_name; obs_base_dir="observables") -> Dict

Compare same observable calculated across different algorithms.

# Returns
Dict with algorithm names as keys, results as values.
"""
function compare_observables_across_algorithms(observable_type::String, model_name::String; obs_base_dir::String="observables")

    obs_base_dir = abspath(obs_base_dir)

    results = query_observables(
        observable_type=observable_type,
        sim_model_name=model_name,
        obs_base_dir=obs_base_dir
    )
    
    by_algorithm = Dict{String, Vector{Dict}}()
    
    for result in results
        algo = result["simulation"]["core"]["algorithm"]
        if !haskey(by_algorithm, algo)
            by_algorithm[algo] = Dict{String, Any}[]
        end
        push!(by_algorithm[algo], result)
    end
    
    return by_algorithm
end

# ============================================================================
# OBSERVABLE QUERY BUILDER (HTML INTERFACE)
# ============================================================================

"""
    open_observable_query_builder(; obs_base_dir="observables")

Open an interactive HTML-based query builder for observables in the default browser.
Generates a user-friendly interface for building query commands.

# Example
```julia
open_observable_query_builder()
open_observable_query_builder(obs_base_dir="custom_obs")
```
"""
function open_observable_query_builder(; obs_base_dir::String="observables")

    obs_base_dir = abspath(obs_base_dir)

    entries = _load_observables_catalog(obs_base_dir=obs_base_dir)
    
    if isempty(entries)
        println("Observable catalog is empty. Run some observable calculations first!")
        return nothing
    end
    
    # Extract unique values for dropdowns
    catalog_info = _extract_observable_catalog_info(entries)
    
    html = _generate_observable_query_builder_html(catalog_info, obs_base_dir)
    
    path = joinpath(tempdir(), "observable_query_builder.html")
    open(path, "w") do f
        write(f, html)
    end
    
    if Sys.islinux()
        run(`xdg-open $path`, wait=false)
    elseif Sys.isapple()
        run(`open $path`, wait=false)
    elseif Sys.iswindows()
        run(`cmd /c start "" "$path"`, wait=false)
    else
        println("Please open manually: $path")
    end
    
    println("✓ Opened observable query builder with $(length(entries)) catalog entries")
    println("  Temp file: $path")
    
    return path
end

"""
Extract observable catalog info organized for query builder dropdowns.
"""
function _extract_observable_catalog_info(entries::Vector{Dict{String, Any}})
    info = Dict{String, Any}(
        "observable_types" => Set{String}(),
        "sim_algorithms" => Set{String}(),
        "sim_models" => Set{String}(),
        "observable_params" => Dict{String, Dict{String, Set}}(),
        "selection_types" => Set{String}()
    )
    
    for entry in entries
        # Skip entries with missing observable structure
        if !haskey(entry, "observable") || !haskey(entry["observable"], "type")
            continue
        end

        # Observable type
        obs_type = entry["observable"]["type"]
        push!(info["observable_types"], obs_type)

        # Track observable params by type
        if !haskey(info["observable_params"], obs_type)
            info["observable_params"][obs_type] = Dict{String, Set}()
        end
        if haskey(entry["observable"], "params") && !isempty(entry["observable"]["params"])
            for (k, v) in entry["observable"]["params"]
                if !haskey(info["observable_params"][obs_type], k)
                    info["observable_params"][obs_type][k] = Set()
                end
                push!(info["observable_params"][obs_type][k], v)
            end
        end

        # Simulation info (guard against missing nested keys)
        if haskey(entry, "simulation")
            sim = entry["simulation"]
            if haskey(sim, "core") && haskey(sim["core"], "algorithm")
                push!(info["sim_algorithms"], sim["core"]["algorithm"])
            end
            if haskey(sim, "model") && haskey(sim["model"], "name")
                push!(info["sim_models"], sim["model"]["name"])
            end
        end

        # Selection type
        if haskey(entry, "analysis_params")
            for (key, val) in entry["analysis_params"]
                if key in ["sweep_selection", "step_selection", "state_selection"] && isa(val, Dict) && haskey(val, "type")
                    push!(info["selection_types"], val["type"])
                end
            end
        end
    end
    
    # Convert Sets to sorted Arrays for JSON
    return _convert_observable_sets_to_arrays(info)
end

function _convert_observable_sets_to_arrays(obj)
    if isa(obj, Set)
        return sort(collect(obj), by=x -> string(x))
    elseif isa(obj, Dict)
        return Dict(k => _convert_observable_sets_to_arrays(v) for (k, v) in obj)
    else
        return obj
    end
end

function _generate_observable_query_builder_html(catalog_info::Dict, obs_base_dir::String)

    obs_base_dir = abspath(obs_base_dir)

    catalog_json = JSON.json(catalog_info)
    
    return """
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Observable Query Builder</title>
    <style>
        * { box-sizing: border-box; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; }
        body { max-width: 1000px; margin: 0 auto; padding: 20px; background: #f5f5f5; }
        h1 { text-align: center; color: #333; margin-bottom: 5px; }
        .subtitle { text-align: center; color: #666; margin-bottom: 30px; }
        .container { display: flex; gap: 30px; }
        .filters-panel { flex: 1; }
        .output-panel { flex: 1; }
        .section { background: white; border-radius: 8px; padding: 20px; margin-bottom: 20px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        .section h2 { margin-top: 0; padding-bottom: 10px; border-bottom: 2px solid #28a745; color: #28a745; font-size: 1.1em; }
        .filter-group { margin-bottom: 15px; }
        .filter-group label { display: block; margin-bottom: 5px; font-weight: 500; color: #555; font-size: 14px; }
        .filter-group select, .filter-group input { width: 100%; padding: 8px 10px; border: 1px solid #ddd; border-radius: 4px; font-size: 14px; }
        .dynamic-params { margin-top: 10px; padding: 10px; background: #f8f9fa; border-radius: 4px; display: none; }
        .dynamic-params.visible { display: block; }
        .dynamic-params h4 { margin: 0 0 10px 0; font-size: 13px; color: #666; }
        .output-box { background: #1e1e1e; color: #d4d4d4; padding: 15px; border-radius: 6px; font-family: monospace; font-size: 13px; line-height: 1.5; white-space: pre-wrap; word-break: break-all; min-height: 150px; }
        .btn { padding: 10px 20px; border: none; border-radius: 6px; cursor: pointer; font-size: 14px; font-weight: 500; width: 100%; margin-top: 10px; }
        .btn-success { background: #28a745; color: white; }
        .btn-success:hover { background: #218838; }
        .btn-secondary { background: #6c757d; color: white; }
        .btn-secondary:hover { background: #5a6268; }
        .info-box { background: #d4edda; border: 1px solid #c3e6cb; border-radius: 4px; padding: 12px; margin-bottom: 15px; font-size: 13px; color: #155724; }
        .copied-toast { position: fixed; bottom: 20px; right: 20px; background: #28a745; color: white; padding: 12px 24px; border-radius: 6px; display: none; }
    </style>
</head>
<body>
    <h1>Observable Query Builder</h1>
    <p class="subtitle">Build query commands for observable calculations</p>
    
    <div class="container">
        <div class="filters-panel">
            <div class="section">
                <h2>Observable</h2>
                <div class="info-box">Query observable calculations from: <code>$obs_base_dir/</code></div>
                <div class="filter-group">
                    <label>Observable Type</label>
                    <select id="filter-observable-type" onchange="onObservableTypeChange()">
                        <option value="">Any</option>
                    </select>
                </div>
                <div id="observable-params" class="dynamic-params">
                    <h4>Observable Parameters</h4>
                    <div id="observable-params-content"></div>
                </div>
            </div>
            
            <div class="section">
                <h2>Simulation Filters</h2>
                <div class="filter-group">
                    <label>Simulation Algorithm</label>
                    <select id="filter-sim-algorithm" onchange="updateCommand()">
                        <option value="">Any</option>
                    </select>
                </div>
                <div class="filter-group">
                    <label>Model</label>
                    <select id="filter-sim-model" onchange="updateCommand()">
                        <option value="">Any</option>
                    </select>
                </div>
            </div>
            
            <div class="section">
                <h2>Analysis</h2>
                <div class="filter-group">
                    <label>Selection Type</label>
                    <select id="filter-selection-type" onchange="updateCommand()">
                        <option value="">Any</option>
                    </select>
                </div>
            </div>
        </div>
        
        <div class="output-panel">
            <div class="section">
                <h2>Generated Command</h2>
                <div class="output-box" id="command-output">query("obs", obs_base_dir="$obs_base_dir")</div>
                <button class="btn btn-success" onclick="copyCommand()">📋 Copy Command</button>
                <button class="btn btn-secondary" onclick="showHelp()">❓ Usage Guide</button>
            </div>
        </div>
    </div>
    
    <div class="copied-toast" id="copied-toast">✓ Copied to clipboard!</div>
    
    <script>
        const catalogData = $catalog_json;
        const baseDir = "$obs_base_dir";
        
        // Populate dropdowns
        function populateDropdowns() {
            // Observable types
            const obsTypeSelect = document.getElementById('filter-observable-type');
            catalogData.observable_types.forEach(type => {
                const option = document.createElement('option');
                option.value = type;
                option.textContent = type;
                obsTypeSelect.appendChild(option);
            });
            
            // Sim algorithms
            const simAlgoSelect = document.getElementById('filter-sim-algorithm');
            catalogData.sim_algorithms.forEach(algo => {
                const option = document.createElement('option');
                option.value = algo;
                option.textContent = algo;
                simAlgoSelect.appendChild(option);
            });
            
            // Sim models
            const simModelSelect = document.getElementById('filter-sim-model');
            catalogData.sim_models.forEach(model => {
                const option = document.createElement('option');
                option.value = model;
                option.textContent = model;
                simModelSelect.appendChild(option);
            });
            
            // Selection types
            const selTypeSelect = document.getElementById('filter-selection-type');
            catalogData.selection_types.forEach(type => {
                const option = document.createElement('option');
                option.value = type;
                option.textContent = type;
                selTypeSelect.appendChild(option);
            });
        }
        
        function onObservableTypeChange() {
            const obsType = document.getElementById('filter-observable-type').value;
            const paramsDiv = document.getElementById('observable-params');
            const contentDiv = document.getElementById('observable-params-content');
            
            contentDiv.innerHTML = '';
            
            if (obsType && catalogData.observable_params[obsType]) {
                const params = catalogData.observable_params[obsType];
                for (const [param, values] of Object.entries(params)) {
                    const group = document.createElement('div');
                    group.className = 'filter-group';
                    group.innerHTML = \`
                        <label>\${param}</label>
                        <select id="filter-obs-\${param}" onchange="updateCommand()">
                            <option value="">Any</option>
                            \${values.map(v => \`<option value="\${v}">\${v}</option>\`).join('')}
                        </select>
                    \`;
                    contentDiv.appendChild(group);
                }
                paramsDiv.classList.add('visible');
            } else {
                paramsDiv.classList.remove('visible');
            }
            
            updateCommand();
        }
        
        function updateCommand() {
            const filters = [];
            
            // Observable type
            const obsType = document.getElementById('filter-observable-type').value;
            if (obsType) filters.push(\`observable_type="\${obsType}"\`);
            
            // Observable params
            if (obsType && catalogData.observable_params[obsType]) {
                for (const param of Object.keys(catalogData.observable_params[obsType])) {
                    const val = document.getElementById(\`filter-obs-\${param}\`)?.value;
                    if (val) filters.push(\`observable_\${param}="\${val}"\`);
                }
            }
            
            // Sim algorithm
            const simAlgo = document.getElementById('filter-sim-algorithm').value;
            if (simAlgo) filters.push(\`sim_algorithm="\${simAlgo}"\`);
            
            // Sim model
            const simModel = document.getElementById('filter-sim-model').value;
            if (simModel) filters.push(\`sim_model_name="\${simModel}"\`);
            
            // Selection type
            const selType = document.getElementById('filter-selection-type').value;
            if (selType) filters.push(\`analysis_selection_type="\${selType}"\`);
            
            // Build command
            let command = 'query("obs"';
            if (baseDir !== 'observables' || filters.length > 0) {
                command += ', ';
            }
            if (baseDir !== 'observables') {
                command += \`obs_base_dir="\${baseDir}"\`;
                if (filters.length > 0) command += ', ';
            }
            command += filters.join(', ');
            command += ')';
            
            document.getElementById('command-output').textContent = command;
        }
        
        function copyCommand() {
            const command = document.getElementById('command-output').textContent;
            navigator.clipboard.writeText(command).then(() => {
                const toast = document.getElementById('copied-toast');
                toast.style.display = 'block';
                setTimeout(() => { toast.style.display = 'none'; }, 2000);
            });
        }
        
        function showHelp() {
            alert(\`Observable Query Builder Help:

1. Select filters to narrow your search
2. Copy the generated command
3. Paste and run in Julia REPL
4. Use display_observable_results(results) to view

Example:
> results = query_observables(observable_type="entanglement_entropy")
> display_observable_results(results)\`);
        }
        
        // Initialize
        populateDropdowns();
        updateCommand();
    </script>
</body>
</html>
"""
end