# ============================================================================
# QUERY INTERFACE FOR SIMULATION CATALOG
# ============================================================================
#
# This module provides query functionality for discovering simulation runs.
# Operates exclusively on run_catalog.jsonl - no file system scanning.
#
# USAGE:
#   results = query_catalog(algorithm="tdvp", N_gte=50)
#   display_results(results)
#   open_query_builder()  # Command generator (recommended)
#   open_query_browser()  # Interactive browser interface
#
# FILTER NAMING CONVENTION:
#   - Core fields: algorithm, system_type, N, S, dtype, status
#   - Algorithm params: algo_<param> (e.g., algo_solver, algo_chi_max)
#   - Model: model_name, model_kind, model_<param> (e.g., model_J)
#   - State: state_kind, state_name, state_<param> (e.g., state_bond_dim)
#   - Results: result_<field> (e.g., result_final_energy)
#
# ============================================================================

using JSON
using Dates
using Printf

# ============================================================================
# PART 1: QUERY FUNCTION
# ============================================================================

"""
    query_catalog(; base_dir="data", filters...) -> Vector{Dict}

Query the catalog for runs matching specified filters.

# Filter Syntax
- Core fields: `algorithm`, `system_type`, `N`, `S`, `dtype`, `status`
- Algorithm params: `algo_<param>` (e.g., `algo_solver`, `algo_chi_max`, `algo_dt`)
- Model: `model_name`, `model_kind`, `model_<param>` (e.g., `model_J`, `model_alpha`)
- State: `state_kind`, `state_name`, `state_<param>` (e.g., `state_bond_dim`)
- Results: `result_<field>` (e.g., `result_final_energy`)

# Comparison Operators
Append suffix to field name:
- `_gt`: greater than
- `_gte`: greater than or equal
- `_lt`: less than
- `_lte`: less than or equal

# Returns
Vector of matching catalog entries with computed `run_dir` path.

# Examples
```julia
results = query_catalog(algorithm="tdvp")
results = query_catalog(algorithm="dmrg", N_gte=50)
results = query_catalog(algorithm="dmrg", algo_solver="lanczos")
results = query_catalog(model_name="long_range_ising", model_alpha_lt=2.0)
results = query_catalog(state_kind="random")
```
"""
function query_catalog(; base_dir::String="data", filters...)

    base_dir = abspath(base_dir)

    entries = _load_catalog(base_dir=base_dir)
    
    if isempty(entries)
        println("Catalog is empty.")
        return Dict{String, Any}[]
    end
    
    results = Dict{String, Any}[]
    
    for entry in entries
        if _matches_filters(entry, filters)
            entry_with_path = copy(entry)
            entry_with_path["run_dir"] = _compute_run_dir(entry, base_dir)
            push!(results, entry_with_path)
        end
    end
    
    return results
end

# ============================================================================
# PART 2: FILTER MATCHING
# ============================================================================

function _matches_filters(entry::Dict, filters)
    for (key, value) in filters
        if !_matches_single_filter(entry, key, value)
            return false
        end
    end
    return true
end

function _matches_single_filter(entry::Dict, key::Symbol, value)
    key_str = String(key)
    op, field_name = _parse_filter_key(key_str)
    field_value = _get_field_value(entry, field_name)
    
    if field_value === nothing
        return false
    end
    
    return _compare(field_value, op, value)
end

function _parse_filter_key(key::String)
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
    _get_field_value(entry, field_name) -> value or nothing

Extract field value from nested entry structure.

Field name patterns:
- "status" -> entry["status"]
- "algorithm" -> entry["core"]["algorithm"]
- "N" -> entry["core"]["N"]
- "algo_solver" -> entry["algorithm_params"]["solver"]
- "algo_chi_max" -> entry["algorithm_params"]["chi_max"]
- "model_name" -> entry["model"]["name"]
- "model_J" -> entry["model"]["params"]["J"]
- "state_kind" -> entry["state"]["kind"]
- "state_name" -> entry["state"]["name"]
- "state_bond_dim" -> entry["state"]["params"]["bond_dim"]
- "result_final_energy" -> entry["results_summary"]["final_energy"]
"""
function _get_field_value(entry::Dict, field_name::String)
    # Top-level fields
    if field_name in ["run_id", "config_hash", "timestamp", "status"]
        return get(entry, field_name, nothing)
    end
    
    # Core fields
    if field_name in ["algorithm", "system_type", "N", "N_spins", "nmax", "S", "dtype"]
        return get(entry["core"], field_name, nothing)
    end
    
    # Algorithm params (with algo_ prefix)
    if startswith(field_name, "algo_")
        algo_key = field_name[6:end]  # Remove "algo_" prefix
        if haskey(entry, "algorithm_params") && haskey(entry["algorithm_params"], algo_key)
            return entry["algorithm_params"][algo_key]
        end
        return nothing
    end
    
    # Model fields (with model_ prefix)
    if startswith(field_name, "model_")
        return _get_model_field(entry, field_name[7:end])
    end
    
    # State fields (with state_ prefix)
    if startswith(field_name, "state_")
        return _get_state_field(entry, field_name[7:end])
    end
    
    # Results summary (with result_ prefix)
    if startswith(field_name, "result_")
        result_field = field_name[8:end]
        return get(get(entry, "results_summary", Dict()), result_field, nothing)
    end
    
    return nothing
end

function _get_model_field(entry::Dict, field_name::String)
    model = get(entry, "model", nothing)
    if model === nothing
        return nothing
    end
    
    # Direct model fields
    if field_name == "name"
        return get(model, "name", nothing)
    elseif field_name == "kind"
        return get(model, "kind", nothing)
    end
    
    # Model params
    params = get(model, "params", nothing)
    if params !== nothing
        return get(params, field_name, nothing)
    end
    
    return nothing
end

function _get_state_field(entry::Dict, field_name::String)
    state = get(entry, "state", nothing)
    if state === nothing
        return nothing
    end
    
    # Direct state fields
    if field_name == "kind"
        return get(state, "kind", nothing)
    elseif field_name == "name"
        return get(state, "name", nothing)
    end
    
    # State params
    params = get(state, "params", nothing)
    if params !== nothing
        return get(params, field_name, nothing)
    end
    
    return nothing
end

function _compare(field_value, op::Symbol, filter_value)
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

function _compute_run_dir(entry::Dict, base_dir::String)

    base_dir = abspath(base_dir)

    algorithm = entry["core"]["algorithm"]
    run_id = entry["run_id"]
    return joinpath(base_dir, algorithm, run_id)
end

# ============================================================================
# PART 4: DISPLAY FUNCTIONS
# ============================================================================

function display_results(results::Vector{Dict{String, Any}}; max_rows::Int=20)
    if isempty(results)
        println("No matching runs found.")
        return
    end
    
    n_results = length(results)
    println("\n", "="^70)
    println("Found $n_results matching run(s)")
    println("="^70)
    
    display_count = min(n_results, max_rows)
    
    for (i, entry) in enumerate(results[1:display_count])
        _display_single_result(entry, i)
    end
    
    if n_results > max_rows
        println("\n... and $(n_results - max_rows) more results")
    end
    
    println("="^70)
end

function _display_single_result(entry::Dict, index::Int)
    println("\n[$index] $(entry["run_id"])")
    println("    Status: $(entry["status"])")
    println("    Algorithm: $(entry["core"]["algorithm"])")
    
    core = entry["core"]
    if haskey(core, "N")
        println("    System: $(core["system_type"]), N=$(core["N"]), S=$(core["S"])")
    else
        println("    System: $(core["system_type"]), N_spins=$(core["N_spins"]), nmax=$(core["nmax"])")
    end
    
    model = entry["model"]
    print("    Model: $(model["name"])")
    if model["kind"] == "prebuilt" && haskey(model, "params")
        params_str = join(["$k=$v" for (k, v) in model["params"]], ", ")
        print(" ($params_str)")
    end
    println()
    
    # State display (only if state exists - ed_spectrum doesn't have initial state)
    if haskey(entry, "state")
        state = entry["state"]
        state_display = get(state, "name", state["kind"])
        print("    State: $state_display")
        if haskey(state, "params") && !isempty(state["params"])
            params_str = join(["$k=$v" for (k, v) in state["params"]], ", ")
            print(" ($params_str)")
        end
        println()
    else
        println("    State: N/A (eigenstate calculation)")
    end
    
    if haskey(entry, "results_summary") && !isempty(entry["results_summary"])
        summary_str = join(["$k=$v" for (k, v) in entry["results_summary"]], ", ")
        println("    Results: $summary_str")
    end
    
    println("    Path: $(entry["run_dir"])")
end

function display_results_compact(results::Vector{Dict{String, Any}})
    if isempty(results)
        println("No matching runs found.")
        return
    end
    
    println("\n", "-"^100)
    @printf("%-28s %-10s %-8s %-6s %-20s %-15s\n", 
            "run_id", "status", "algo", "N", "model", "state")
    println("-"^100)
    
    for entry in results
        run_id = entry["run_id"]
        status = entry["status"]
        algo = entry["core"]["algorithm"]
        N = get(entry["core"], "N", get(entry["core"], "N_spins", "-"))
        model = entry["model"]["name"]
        state = haskey(entry, "state") ? get(entry["state"], "name", entry["state"]["kind"]) : "N/A"
        
        @printf("%-28s %-10s %-8s %-6s %-20s %-15s\n",
                run_id, status, algo, N, model, state)
    end
    
    println("-"^100)
    println("Total: $(length(results)) run(s)")
end

# ============================================================================
# PART 5: CONVENIENCE FUNCTIONS
# ============================================================================

function get_run_ids(results::Vector{Dict{String, Any}})
    return [r["run_id"] for r in results]
end

function get_run_dirs(results::Vector{Dict{String, Any}})
    return [r["run_dir"] for r in results]
end

function load_config(result::Dict; base_dir::String="data")

    base_dir = abspath(base_dir)    

    run_dir = get(result, "run_dir", nothing)
    
    if run_dir === nothing
        run_dir = _compute_run_dir(result, base_dir)
    end
    
    config_path = joinpath(run_dir, "config.json")
    
    if !isfile(config_path)
        error("Config file not found: $config_path")
    end
    
    return JSON.parsefile(config_path)
end

function list_available_models(; base_dir::String="data")

    base_dir = abspath(base_dir)

    entries = _load_catalog(base_dir=base_dir)
    models = Set{String}()
    for entry in entries
        push!(models, entry["model"]["name"])
    end
    return sort(collect(models))
end

function list_available_algorithms(; base_dir::String="data")

    base_dir = abspath(base_dir)

    entries = _load_catalog(base_dir=base_dir)
    algorithms = Set{String}()
    for entry in entries
        push!(algorithms, entry["core"]["algorithm"])
    end
    return sort(collect(algorithms))
end

function catalog_summary(; base_dir::String="data")

    base_dir = abspath(base_dir)

    entries = _load_catalog(base_dir=base_dir)
    
    if isempty(entries)
        println("Catalog is empty.")
        return
    end
    
    status_counts = Dict{String, Int}()
    algo_counts = Dict{String, Int}()
    model_counts = Dict{String, Int}()
    
    for entry in entries
        status = entry["status"]
        algo = entry["core"]["algorithm"]
        model = entry["model"]["name"]
        
        status_counts[status] = get(status_counts, status, 0) + 1
        algo_counts[algo] = get(algo_counts, algo, 0) + 1
        model_counts[model] = get(model_counts, model, 0) + 1
    end
    
    println("\n", "="^50)
    println("CATALOG SUMMARY")
    println("="^50)
    println("Total runs: $(length(entries))")
    
    println("\nBy status:")
    for (status, count) in sort(collect(status_counts))
        println("  $status: $count")
    end
    
    println("\nBy algorithm:")
    for (algo, count) in sort(collect(algo_counts))
        println("  $algo: $count")
    end
    
    println("\nBy model:")
    for (model, count) in sort(collect(model_counts))
        println("  $model: $count")
    end
    
    println("="^50)
end

# ============================================================================
# PART 6: BROWSER QUERY INTERFACE (Interactive - JS does filtering)
# ============================================================================

"""
    open_query_browser(; base_dir="data")

Open interactive query browser in default web browser.
All filters are dynamically populated from catalog data.
JavaScript performs the filtering and displays results directly.

# Usage
```julia
open_query_browser()
```
"""
function open_query_browser(; base_dir::String="data")

    base_dir = abspath(base_dir)

    entries = _load_catalog(base_dir=base_dir)
    
    for entry in entries
        entry["run_dir"] = _compute_run_dir(entry, base_dir)
    end
    
    html = _generate_query_browser_html(entries)
    
    path = joinpath(tempdir(), "tn_query_browser.html")
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
    
    println("✓ Opened query browser with $(length(entries)) catalog entries")
    println("  Temp file: $path")
    
    return path
end

function _generate_query_browser_html(entries::Vector{Dict{String, Any}})
    catalog_json = JSON.json(entries)
    
    return """
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>TNCodebase Query Browser</title>
    <style>
        * { box-sizing: border-box; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; }
        body { max-width: 1400px; margin: 0 auto; padding: 20px; background: #f5f5f5; }
        h1 { text-align: center; color: #333; margin-bottom: 10px; }
        .subtitle { text-align: center; color: #666; margin-bottom: 30px; }
        .container { display: flex; gap: 30px; }
        .filter-container { flex: 0 0 350px; }
        .results-container { flex: 1; min-width: 0; }
        .section { background: white; border-radius: 8px; padding: 20px; margin-bottom: 20px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        .section h2 { margin-top: 0; padding-bottom: 10px; border-bottom: 2px solid #4a90d9; color: #4a90d9; font-size: 1.2em; }
        .filter-group { margin-bottom: 15px; }
        .filter-group label { display: block; margin-bottom: 5px; font-weight: 500; color: #555; }
        .filter-group select { width: 100%; padding: 8px; border: 1px solid #ddd; border-radius: 4px; font-size: 14px; }
        .btn { padding: 10px 20px; border: none; border-radius: 6px; cursor: pointer; font-size: 14px; font-weight: 500; width: 100%; margin-top: 10px; }
        .btn-primary { background: #4a90d9; color: white; }
        .btn-primary:hover { background: #3a7bc8; }
        .btn-secondary { background: #6c757d; color: white; }
        .stats { background: #e7f3ff; border-radius: 6px; padding: 15px; margin-bottom: 20px; display: flex; justify-content: space-around; text-align: center; }
        .stat-value { font-size: 24px; font-weight: bold; color: #4a90d9; }
        .stat-label { font-size: 12px; color: #666; }
        .results-table { width: 100%; border-collapse: collapse; font-size: 13px; }
        .results-table th { background: #4a90d9; color: white; padding: 12px 8px; text-align: left; }
        .results-table td { padding: 10px 8px; border-bottom: 1px solid #eee; }
        .results-table tr:hover { background: #f5f9ff; cursor: pointer; }
        .results-table tr.selected { background: #e7f3ff; }
        .status-completed { color: #28a745; font-weight: 500; }
        .status-failed { color: #dc3545; font-weight: 500; }
        .no-results { text-align: center; padding: 40px; color: #666; }
        .detail-panel { background: #f8f9fa; border-radius: 6px; padding: 15px; margin-top: 20px; display: none; }
        .detail-panel.visible { display: block; }
        .detail-grid { display: grid; grid-template-columns: repeat(2, 1fr); gap: 15px; }
        .detail-section { background: white; border-radius: 4px; padding: 12px; }
        .detail-section h4 { margin: 0 0 10px 0; color: #4a90d9; font-size: 14px; }
        .detail-item { display: flex; justify-content: space-between; padding: 4px 0; font-size: 13px; }
        .detail-item .key { color: #666; }
        .detail-item .value { color: #333; font-weight: 500; }
        .path-box { background: #1e1e1e; color: #d4d4d4; padding: 12px; border-radius: 4px; font-family: monospace; font-size: 13px; margin-top: 10px; word-break: break-all; }
        .copy-btn { background: #28a745; color: white; border: none; padding: 6px 12px; border-radius: 4px; cursor: pointer; font-size: 12px; margin-left: 10px; }
        .results-wrapper { max-height: 500px; overflow-y: auto; border: 1px solid #ddd; border-radius: 6px; }
    </style>
</head>
<body>
    <h1>TNCodebase Query Browser</h1>
    <p class="subtitle">Interactive catalog exploration</p>
    
    <div id="main-content" class="container">
        <div class="filter-container">
            <div class="section">
                <h2>Filters</h2>
                <div class="filter-group"><label>Status</label><select id="filter-status" onchange="applyFilters()"><option value="">Any</option></select></div>
                <div class="filter-group"><label>Algorithm</label><select id="filter-algorithm" onchange="applyFilters()"><option value="">Any</option></select></div>
                <div class="filter-group"><label>System Type</label><select id="filter-system-type" onchange="applyFilters()"><option value="">Any</option></select></div>
                <div class="filter-group"><label>Model</label><select id="filter-model" onchange="applyFilters()"><option value="">Any</option></select></div>
                <div class="filter-group"><label>State Kind</label><select id="filter-state-kind" onchange="applyFilters()"><option value="">Any</option></select></div>
                <button class="btn btn-primary" onclick="applyFilters()">Apply Filters</button>
                <button class="btn btn-secondary" onclick="clearFilters()">Clear All</button>
            </div>
        </div>
        
        <div class="results-container">
            <div class="stats">
                <div><span class="stat-value" id="stat-total">0</span><br><span class="stat-label">Total</span></div>
                <div><span class="stat-value" id="stat-matched">0</span><br><span class="stat-label">Matched</span></div>
                <div><span class="stat-value" id="stat-completed">0</span><br><span class="stat-label">Completed</span></div>
            </div>
            <div class="section">
                <h2>Results</h2>
                <div class="results-wrapper">
                    <table class="results-table">
                        <thead><tr><th>Run ID</th><th>Status</th><th>Algo</th><th>N</th><th>Model</th><th>State</th></tr></thead>
                        <tbody id="results-body"></tbody>
                    </table>
                </div>
                <div id="detail-panel" class="detail-panel">
                    <h3>Run Details</h3>
                    <div class="detail-grid">
                        <div class="detail-section"><h4>Core</h4><div id="detail-core"></div></div>
                        <div class="detail-section"><h4>Algorithm</h4><div id="detail-algorithm"></div></div>
                        <div class="detail-section"><h4>Model</h4><div id="detail-model"></div></div>
                        <div class="detail-section"><h4>State</h4><div id="detail-state"></div></div>
                    </div>
                    <div class="detail-section" style="margin-top:15px;"><h4>Results</h4><div id="detail-results"></div></div>
                    <div style="margin-top:15px;"><strong>Path:</strong><button class="copy-btn" onclick="copyPath()">Copy</button><div class="path-box" id="detail-path"></div></div>
                </div>
            </div>
        </div>
    </div>
    
    <script>
        const CATALOG_DATA = $(catalog_json);
        let catalogData = [], filteredData = [], selectedRun = null;
        
        function initialize() {
            if (!CATALOG_DATA || CATALOG_DATA.length === 0) { document.body.innerHTML = '<h1>No catalog data</h1>'; return; }
            catalogData = CATALOG_DATA; filteredData = [...catalogData];
            populateDropdowns(); updateStats(); renderResults();
        }
        
        function populateDropdowns() {
            const statuses = [...new Set(catalogData.map(e => e.status))].sort();
            const algos = [...new Set(catalogData.map(e => e.core.algorithm))].sort();
            const sysTypes = [...new Set(catalogData.map(e => e.core.system_type))].sort();
            const models = [...new Set(catalogData.map(e => e.model.name))].sort();
            const stateKinds = [...new Set(catalogData.map(e => e.state.kind))].sort();
            
            populateSelect('filter-status', statuses);
            populateSelect('filter-algorithm', algos, v => v.toUpperCase());
            populateSelect('filter-system-type', sysTypes);
            populateSelect('filter-model', models, formatModelName);
            populateSelect('filter-state-kind', stateKinds, capitalize);
        }
        
        function populateSelect(id, values, formatter = v => v) {
            const sel = document.getElementById(id);
            values.forEach(v => { const o = document.createElement('option'); o.value = v; o.textContent = formatter(v); sel.appendChild(o); });
        }
        
        function applyFilters() {
            filteredData = catalogData.filter(e => {
                const status = document.getElementById('filter-status').value;
                if (status && e.status !== status) return false;
                const algo = document.getElementById('filter-algorithm').value;
                if (algo && e.core.algorithm !== algo) return false;
                const sysType = document.getElementById('filter-system-type').value;
                if (sysType && e.core.system_type !== sysType) return false;
                const model = document.getElementById('filter-model').value;
                if (model && e.model.name !== model) return false;
                const stateKind = document.getElementById('filter-state-kind').value;
                if (stateKind && e.state.kind !== stateKind) return false;
                return true;
            });
            updateStats(); renderResults();
        }
        
        function clearFilters() {
            document.querySelectorAll('select').forEach(s => s.value = '');
            filteredData = [...catalogData]; updateStats(); renderResults(); hideDetail();
        }
        
        function updateStats() {
            document.getElementById('stat-total').textContent = catalogData.length;
            document.getElementById('stat-matched').textContent = filteredData.length;
            document.getElementById('stat-completed').textContent = filteredData.filter(e => e.status === 'completed').length;
        }
        
        function renderResults() {
            const tbody = document.getElementById('results-body');
            if (filteredData.length === 0) { tbody.innerHTML = '<tr><td colspan="6" class="no-results">No matching runs</td></tr>'; return; }
            tbody.innerHTML = filteredData.map((e, i) => \`<tr onclick="selectRun(\${i})" class="\${selectedRun===i?'selected':''}"><td>\${e.run_id}</td><td class="status-\${e.status}">\${e.status}</td><td>\${e.core.algorithm.toUpperCase()}</td><td>\${e.core.N||e.core.N_spins||'-'}</td><td>\${formatModelName(e.model.name)}</td><td>\${capitalize(e.state.name||e.state.kind)}</td></tr>\`).join('');
        }
        
        function selectRun(i) { selectedRun = i; renderResults(); showDetail(filteredData[i]); }
        function hideDetail() { selectedRun = null; document.getElementById('detail-panel').classList.remove('visible'); }
        
        function showDetail(e) {
            document.getElementById('detail-panel').classList.add('visible');
            document.getElementById('detail-core').innerHTML = renderItems(e.core);
            document.getElementById('detail-algorithm').innerHTML = renderItems(e.algorithm_params||{});
            document.getElementById('detail-model').innerHTML = renderItems({kind:e.model.kind,name:e.model.name,...e.model.params});
            document.getElementById('detail-state').innerHTML = renderItems({kind:e.state.kind,name:e.state.name||'-',...e.state.params});
            document.getElementById('detail-results').innerHTML = e.results_summary?renderItems(e.results_summary):'<em>None</em>';
            document.getElementById('detail-path').textContent = e.run_dir;
        }
        
        function renderItems(obj) { return Object.entries(obj).map(([k,v])=>\`<div class="detail-item"><span class="key">\${k}</span><span class="value">\${formatVal(v)}</span></div>\`).join(''); }
        function formatVal(v) { return typeof v==='number'?(Math.abs(v)<0.0001||Math.abs(v)>=10000?v.toExponential(4):v):v; }
        function formatModelName(n) { return n.split('_').map(capitalize).join(' '); }
        function capitalize(s) { return s?s.charAt(0).toUpperCase()+s.slice(1):''; }
        function copyPath() { navigator.clipboard.writeText(document.getElementById('detail-path').textContent).then(()=>alert('Copied!')); }
        
        window.onload = initialize;
    </script>
</body>
</html>
"""
end

# ============================================================================
# PART 7: QUERY BUILDER (Command Generator - Julia does filtering)
# ============================================================================

"""
    open_query_builder(; base_dir="data")

Open query builder in browser. Generates Julia commands to copy/paste.
More stable than interactive browser - Julia does actual filtering.
Features cascading filters based on catalog content.

# Usage
```julia
open_query_builder()
# → Opens browser with cascading dropdowns
# → Copy generated command
# → Paste in Julia REPL
```
"""
function open_query_builder(; base_dir::String="data")

    base_dir = abspath(base_dir)

    entries = _load_catalog(base_dir=base_dir)
    
    # Extract unique values for dropdowns
    catalog_info = _extract_catalog_info(entries)
    
    html = _generate_query_builder_html(catalog_info, base_dir)
    
    path = joinpath(tempdir(), "tn_query_builder.html")
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
    
    println("✓ Opened query builder with $(length(entries)) catalog entries")
    println("  Temp file: $path")
    
    return path
end

"""
Extract catalog info organized for cascading dropdowns.
"""
function _extract_catalog_info(entries::Vector{Dict{String, Any}})
    info = Dict{String, Any}(
        "algorithms" => Dict{String, Any}(),
        "models" => Dict{String, Any}(),
        "states_by_kind" => Dict{String, Any}(),
        "core" => Dict{String, Set}(
            "system_type" => Set{String}(),
            "S" => Set{Any}(),
            "dtype" => Set{String}()
        ),
        "N_values" => Set{Int}()
    )
    
    for entry in entries
        algo = entry["core"]["algorithm"]
        
        # Algorithm params grouped by algorithm
        if !haskey(info["algorithms"], algo)
            info["algorithms"][algo] = Dict{String, Set}()
        end
        if haskey(entry, "algorithm_params")
            for (k, v) in entry["algorithm_params"]
                if !haskey(info["algorithms"][algo], k)
                    info["algorithms"][algo][k] = Set()
                end
                push!(info["algorithms"][algo][k], v)
            end
        end
        
        # Model params grouped by model name
        model_name = entry["model"]["name"]
        if !haskey(info["models"], model_name)
            info["models"][model_name] = Dict{String, Any}(
                "kind" => entry["model"]["kind"],
                "params" => Dict{String, Set}()
            )
        end
        if haskey(entry["model"], "params")
            for (k, v) in entry["model"]["params"]
                if !haskey(info["models"][model_name]["params"], k)
                    info["models"][model_name]["params"][k] = Set()
                end
                push!(info["models"][model_name]["params"][k], v)
            end
        end
        
        # State: organized by kind, then by name within kind
        # (Only process if state exists - ed_spectrum doesn't have initial state)
        if haskey(entry, "state")
            state_kind = entry["state"]["kind"]
            state_name = get(entry["state"], "name", nothing)
            
            if !haskey(info["states_by_kind"], state_kind)
                info["states_by_kind"][state_kind] = Dict{String, Any}(
                    "names" => Dict{String, Any}(),
                    "params" => Dict{String, Set}()
                )
            end
            
            # For prebuilt states, track names and their params
            if state_kind == "prebuilt" && state_name !== nothing
                if !haskey(info["states_by_kind"][state_kind]["names"], state_name)
                    info["states_by_kind"][state_kind]["names"][state_name] = Dict{String, Set}()
                end
                if haskey(entry["state"], "params")
                    for (k, v) in entry["state"]["params"]
                        if !haskey(info["states_by_kind"][state_kind]["names"][state_name], k)
                            info["states_by_kind"][state_kind]["names"][state_name][k] = Set()
                        end
                        push!(info["states_by_kind"][state_kind]["names"][state_name][k], v)
                    end
                end
            end
            
            # For random/custom states, track params at kind level
            if state_kind in ["random", "custom"]
                if haskey(entry["state"], "params")
                    for (k, v) in entry["state"]["params"]
                        if !haskey(info["states_by_kind"][state_kind]["params"], k)
                            info["states_by_kind"][state_kind]["params"][k] = Set()
                        end
                        push!(info["states_by_kind"][state_kind]["params"][k], v)
                    end
                end
            end
        end
        
        # Core values
        push!(info["core"]["system_type"], entry["core"]["system_type"])
        push!(info["core"]["S"], entry["core"]["S"])
        push!(info["core"]["dtype"], entry["core"]["dtype"])
        
        N = get(entry["core"], "N", get(entry["core"], "N_spins", nothing))
        if N !== nothing
            push!(info["N_values"], N)
        end
    end
    
    # Convert Sets to sorted Arrays for JSON
    return _convert_sets_to_arrays(info)
end

function _convert_sets_to_arrays(obj)
    if isa(obj, Set)
        return sort(collect(obj), by=x -> string(x))
    elseif isa(obj, Dict)
        return Dict(k => _convert_sets_to_arrays(v) for (k, v) in obj)
    else
        return obj
    end
end

function _generate_query_builder_html(catalog_info::Dict, base_dir::String)
    catalog_json = JSON.json(catalog_info)
    
    return """
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>TNCodebase Query Builder</title>
    <style>
        * { box-sizing: border-box; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; }
        body { max-width: 1000px; margin: 0 auto; padding: 20px; background: #f5f5f5; }
        h1 { text-align: center; color: #333; margin-bottom: 5px; }
        .subtitle { text-align: center; color: #666; margin-bottom: 30px; }
        .container { display: flex; gap: 30px; }
        .filters-panel { flex: 1; }
        .output-panel { flex: 1; }
        .section { background: white; border-radius: 8px; padding: 20px; margin-bottom: 20px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        .section h2 { margin-top: 0; padding-bottom: 10px; border-bottom: 2px solid #4a90d9; color: #4a90d9; font-size: 1.1em; }
        .filter-group { margin-bottom: 15px; }
        .filter-group label { display: block; margin-bottom: 5px; font-weight: 500; color: #555; font-size: 14px; }
        .filter-group select, .filter-group input { width: 100%; padding: 8px 10px; border: 1px solid #ddd; border-radius: 4px; font-size: 14px; }
        .filter-row { display: flex; gap: 8px; }
        .filter-row select.op-select { width: 75px; flex-shrink: 0; }
        .filter-row input { flex: 1; }
        .dynamic-params { margin-top: 10px; padding: 10px; background: #f8f9fa; border-radius: 4px; display: none; }
        .dynamic-params.visible { display: block; }
        .dynamic-params h4 { margin: 0 0 10px 0; font-size: 13px; color: #666; }
        .output-box { background: #1e1e1e; color: #d4d4d4; padding: 15px; border-radius: 6px; font-family: monospace; font-size: 13px; line-height: 1.5; white-space: pre-wrap; word-break: break-all; min-height: 150px; }
        .btn { padding: 10px 20px; border: none; border-radius: 6px; cursor: pointer; font-size: 14px; font-weight: 500; width: 100%; margin-top: 10px; }
        .btn-success { background: #28a745; color: white; }
        .btn-success:hover { background: #218838; }
        .btn-secondary { background: #6c757d; color: white; }
        .btn-secondary:hover { background: #5a6268; }
        .info-box { background: #e7f3ff; border: 1px solid #b8daff; border-radius: 4px; padding: 12px; margin-bottom: 15px; font-size: 13px; color: #004085; }
        .workflow-box { background: #f8f9fa; border-radius: 6px; padding: 15px; margin-top: 15px; font-size: 13px; }
        .workflow-box h4 { margin: 0 0 10px 0; color: #333; }
        .workflow-box ol { margin: 0; padding-left: 20px; }
        .workflow-box li { margin-bottom: 5px; }
        .workflow-box code { background: #e9ecef; padding: 2px 6px; border-radius: 3px; font-size: 12px; }
        .copied-toast { position: fixed; bottom: 20px; right: 20px; background: #28a745; color: white; padding: 12px 24px; border-radius: 6px; display: none; }
    </style>
</head>
<body>
    <h1>TNCodebase Query Builder</h1>
    <p class="subtitle">Build query commands — Julia does the actual filtering</p>
    
    <div class="container">
        <div class="filters-panel">
            <div class="section">
                <h2>Core Filters</h2>
                <div class="filter-group"><label>Status</label><select id="filter-status" onchange="updateCommand()"><option value="">Any</option><option value="completed">Completed</option><option value="failed">Failed</option></select></div>
                <div class="filter-group"><label>System Type</label><select id="filter-system-type" onchange="updateCommand()"><option value="">Any</option></select></div>
                <div class="filter-group"><label>N (System Size)</label><div class="filter-row"><select id="filter-N-op" class="op-select" onchange="updateCommand()"><option value="">Any</option><option value="eq">=</option><option value="gt">></option><option value="gte">≥</option><option value="lt"><</option><option value="lte">≤</option></select><input type="number" id="filter-N-val" placeholder="Value" oninput="updateCommand()"></div></div>
            </div>
            
            <div class="section">
                <h2>Algorithm</h2>
                <div class="filter-group"><label>Algorithm</label><select id="filter-algorithm" onchange="onAlgorithmChange()"><option value="">Any</option></select></div>
                <div id="algorithm-params" class="dynamic-params"><h4>Algorithm Parameters</h4><div id="algorithm-params-content"></div></div>
            </div>
            
            <div class="section">
                <h2>Model</h2>
                <div class="filter-group"><label>Model Name</label><select id="filter-model" onchange="onModelChange()"><option value="">Any</option></select></div>
                <div id="model-params" class="dynamic-params"><h4>Model Parameters</h4><div id="model-params-content"></div></div>
            </div>
            
            <div class="section">
                <h2>State</h2>
                <div class="filter-group"><label>State Kind</label><select id="filter-state-kind" onchange="onStateKindChange()"><option value="">Any</option></select></div>
                <div id="state-name-container" class="filter-group" style="display:none;"><label>State Name</label><select id="filter-state-name" onchange="onStateNameChange()"><option value="">Any</option></select></div>
                <div id="state-params" class="dynamic-params"><h4>State Parameters</h4><div id="state-params-content"></div></div>
            </div>
            
            <button class="btn btn-secondary" onclick="clearAll()">Clear All Filters</button>
        </div>
        
        <div class="output-panel">
            <div class="section">
                <h2>Generated Julia Command</h2>
                <div class="info-box">Copy this command and run in Julia REPL to execute the query.</div>
                <div class="output-box" id="output-command">results = query("sim")</div>
                <button class="btn btn-success" onclick="copyCommand()">📋 Copy Command</button>
                <div class="workflow-box">
                    <h4>Workflow</h4>
                    <ol>
                        <li>Select filters on the left</li>
                        <li>Click <strong>Copy Command</strong></li>
                        <li>Paste in Julia REPL</li>
                        <li>Run <code>display_results(results)</code></li>
                        <li>Use <code>load_config(results[1])</code> to get config</li>
                    </ol>
                </div>
            </div>
            <div class="section">
                <h2>Quick Reference</h2>
                <div style="font-size:13px;color:#555;">
                    <code style="display:block;background:#f4f4f4;padding:10px;border-radius:4px;">
display_results(results)<br>
display_results_compact(results)<br>
get_run_dirs(results)<br>
config = load_config(results[1])
                    </code>
                </div>
            </div>
        </div>
    </div>
    
    <div class="copied-toast" id="toast">✓ Copied to clipboard!</div>
    
    <script>
        const CATALOG_INFO = $(catalog_json);
        const BASE_DIR = "$(base_dir)";
        
        function initialize() {
            populateBaseDropdowns();
            updateCommand();
        }
        
        function populateBaseDropdowns() {
            // System types
            const sysSelect = document.getElementById('filter-system-type');
            CATALOG_INFO.core.system_type.forEach(sys => {
                const opt = document.createElement('option');
                opt.value = sys; opt.textContent = sys === 'spinboson' ? 'Spin-Boson' : capitalize(sys);
                sysSelect.appendChild(opt);
            });
            
            // Algorithms
            const algoSelect = document.getElementById('filter-algorithm');
            Object.keys(CATALOG_INFO.algorithms).sort().forEach(algo => {
                const opt = document.createElement('option');
                opt.value = algo; opt.textContent = algo.toUpperCase();
                algoSelect.appendChild(opt);
            });
            
            // Models
            const modelSelect = document.getElementById('filter-model');
            Object.keys(CATALOG_INFO.models).sort().forEach(model => {
                const opt = document.createElement('option');
                opt.value = model; opt.textContent = formatModelName(model);
                modelSelect.appendChild(opt);
            });
            
            // State Kinds
            const stateKindSelect = document.getElementById('filter-state-kind');
            Object.keys(CATALOG_INFO.states_by_kind).sort().forEach(kind => {
                const opt = document.createElement('option');
                opt.value = kind; opt.textContent = capitalize(kind);
                stateKindSelect.appendChild(opt);
            });
        }
        
        function onAlgorithmChange() {
            const algo = document.getElementById('filter-algorithm').value;
            const container = document.getElementById('algorithm-params');
            const content = document.getElementById('algorithm-params-content');
            
            if (!algo || !CATALOG_INFO.algorithms[algo]) {
                container.classList.remove('visible'); content.innerHTML = '';
                updateCommand(); return;
            }
            
            const params = CATALOG_INFO.algorithms[algo];
            let html = '';
            Object.keys(params).sort().forEach(key => {
                const values = params[key];
                if (values.every(v => typeof v === 'number')) {
                    html += buildNumericFilter('algo_' + key, formatParamName(key));
                } else {
                    html += buildSelectFilter('algo_' + key, formatParamName(key), values);
                }
            });
            content.innerHTML = html;
            container.classList.add('visible');
            updateCommand();
        }
        
        function onModelChange() {
            const model = document.getElementById('filter-model').value;
            const container = document.getElementById('model-params');
            const content = document.getElementById('model-params-content');
            
            if (!model || !CATALOG_INFO.models[model]) {
                container.classList.remove('visible'); content.innerHTML = '';
                updateCommand(); return;
            }
            
            const params = CATALOG_INFO.models[model].params;
            let html = '';
            Object.keys(params).sort().forEach(key => {
                const values = params[key];
                if (values.every(v => typeof v === 'number')) {
                    html += buildNumericFilter('model_' + key, formatParamName(key));
                } else {
                    html += buildSelectFilter('model_' + key, formatParamName(key), values);
                }
            });
            content.innerHTML = html || '<div style="color:#888;">No parameters</div>';
            container.classList.add('visible');
            updateCommand();
        }
        
        function onStateKindChange() {
            const kind = document.getElementById('filter-state-kind').value;
            const nameContainer = document.getElementById('state-name-container');
            const nameSelect = document.getElementById('filter-state-name');
            const paramsContainer = document.getElementById('state-params');
            const paramsContent = document.getElementById('state-params-content');
            
            nameSelect.innerHTML = '<option value="">Any</option>';
            paramsContent.innerHTML = '';
            paramsContainer.classList.remove('visible');
            nameContainer.style.display = 'none';
            
            if (!kind || !CATALOG_INFO.states_by_kind[kind]) { updateCommand(); return; }
            
            const stateInfo = CATALOG_INFO.states_by_kind[kind];
            
            // For prebuilt: show name dropdown
            if (kind === 'prebuilt' && stateInfo.names && Object.keys(stateInfo.names).length > 0) {
                nameContainer.style.display = 'block';
                Object.keys(stateInfo.names).sort().forEach(name => {
                    const opt = document.createElement('option');
                    opt.value = name; opt.textContent = capitalize(name);
                    nameSelect.appendChild(opt);
                });
            }
            
            // For random/custom: show params directly
            if ((kind === 'random' || kind === 'custom') && stateInfo.params && Object.keys(stateInfo.params).length > 0) {
                let html = '';
                Object.keys(stateInfo.params).sort().forEach(key => {
                    const values = stateInfo.params[key];
                    if (values.every(v => typeof v === 'number')) {
                        html += buildNumericFilter('state_' + key, formatParamName(key));
                    } else {
                        html += buildSelectFilter('state_' + key, formatParamName(key), values);
                    }
                });
                paramsContent.innerHTML = html;
                paramsContainer.classList.add('visible');
            }
            updateCommand();
        }
        
        function onStateNameChange() {
            const kind = document.getElementById('filter-state-kind').value;
            const name = document.getElementById('filter-state-name').value;
            const paramsContainer = document.getElementById('state-params');
            const paramsContent = document.getElementById('state-params-content');
            
            paramsContent.innerHTML = '';
            paramsContainer.classList.remove('visible');
            
            if (!kind || kind !== 'prebuilt' || !name) { updateCommand(); return; }
            
            const stateInfo = CATALOG_INFO.states_by_kind[kind];
            if (!stateInfo.names || !stateInfo.names[name]) { updateCommand(); return; }
            
            const params = stateInfo.names[name];
            let html = '';
            Object.keys(params).sort().forEach(key => {
                const values = params[key];
                if (values.every(v => typeof v === 'number')) {
                    html += buildNumericFilter('state_' + key, formatParamName(key));
                } else {
                    html += buildSelectFilter('state_' + key, formatParamName(key), values);
                }
            });
            if (html) { paramsContent.innerHTML = html; paramsContainer.classList.add('visible'); }
            updateCommand();
        }
        
        function buildSelectFilter(id, label, values) {
            let options = '<option value="">Any</option>';
            values.forEach(v => { options += \`<option value="\${v}">\${v}</option>\`; });
            return \`<div class="filter-group"><label>\${label}</label><select id="filter-\${id}" onchange="updateCommand()">\${options}</select></div>\`;
        }
        
        function buildNumericFilter(id, label) {
            return \`<div class="filter-group"><label>\${label}</label><div class="filter-row"><select id="filter-\${id}-op" class="op-select" onchange="updateCommand()"><option value="">Any</option><option value="eq">=</option><option value="gt">></option><option value="gte">≥</option><option value="lt"><</option><option value="lte">≤</option></select><input type="number" step="any" id="filter-\${id}-val" placeholder="Value" oninput="updateCommand()"></div></div>\`;
        }
        
        function updateCommand() {
            const filters = [];
            if (BASE_DIR !== "data") filters.push(\`base_dir="\${BASE_DIR}"\`);
            
            const status = document.getElementById('filter-status').value;
            if (status) filters.push(\`status="\${status}"\`);
            
            const sysType = document.getElementById('filter-system-type').value;
            if (sysType) filters.push(\`system_type="\${sysType}"\`);
            
            const nOp = document.getElementById('filter-N-op').value;
            const nVal = document.getElementById('filter-N-val').value;
            if (nOp && nVal) filters.push(\`N\${opToSuffix(nOp)}=\${nVal}\`);
            
            const algo = document.getElementById('filter-algorithm').value;
            if (algo) filters.push(\`algorithm="\${algo}"\`);
            collectDynamicFilters('algorithm-params-content', 'algo_', filters);
            
            const model = document.getElementById('filter-model').value;
            if (model) filters.push(\`model_name="\${model}"\`);
            collectDynamicFilters('model-params-content', 'model_', filters);
            
            const stateKind = document.getElementById('filter-state-kind').value;
            if (stateKind) filters.push(\`state_kind="\${stateKind}"\`);
            
            const stateName = document.getElementById('filter-state-name').value;
            if (stateName) filters.push(\`state_name="\${stateName}"\`);
            collectDynamicFilters('state-params-content', 'state_', filters);
            
            let cmd = 'results = query("sim"';
            if (filters.length > 0) {
                cmd += ', ';
                if (filters.length <= 2) { cmd += filters.join(', '); }
                else { cmd += '\\n    ' + filters.join(',\\n    ') + '\\n'; }
            }
            cmd += ')';
            document.getElementById('output-command').textContent = cmd;
        }
        
        function collectDynamicFilters(containerId, prefix, filters) {
            const container = document.getElementById(containerId);
            if (!container) return;
            
            container.querySelectorAll('select:not(.op-select)').forEach(select => {
                if (select.value) {
                    const key = select.id.replace('filter-', '');
                    const val = select.value;
                    if (!isNaN(parseFloat(val)) && isFinite(val)) { filters.push(\`\${key}=\${val}\`); }
                    else { filters.push(\`\${key}="\${val}"\`); }
                }
            });
            
            container.querySelectorAll('.op-select').forEach(opSelect => {
                const baseId = opSelect.id.replace('filter-', '').replace('-op', '');
                const op = opSelect.value;
                const valInput = document.getElementById('filter-' + baseId + '-val');
                const val = valInput ? valInput.value : '';
                if (op && val) { filters.push(\`\${baseId}\${opToSuffix(op)}=\${val}\`); }
            });
        }
        
        function opToSuffix(op) {
            switch(op) { case 'eq': return ''; case 'gt': return '_gt'; case 'gte': return '_gte'; case 'lt': return '_lt'; case 'lte': return '_lte'; default: return ''; }
        }
        
        function formatModelName(n) { return n.split('_').map(capitalize).join(' '); }
        function formatParamName(n) {
            const m = {'chi_max':'χ_max','dt':'dt','n_sweeps':'n_sweeps','cutoff':'cutoff','krylov_dim':'krylov_dim','tol':'tol','max_iter':'max_iter','evol_type':'evol_type','J':'J','h':'h','Jx':'Jx','Jy':'Jy','Jz':'Jz','hx':'hx','hy':'hy','hz':'hz','alpha':'α','n_exp':'n_exp','omega':'ω','g':'g','coupling_dir':'coupling_dir','field_dir':'field_dir','spin_direction':'spin_direction','eigenstate':'eigenstate','even_state':'even_state','odd_state':'odd_state','bond_dim':'bond_dim'};
            return m[n]||n;
        }
        function capitalize(s) { return s?s.charAt(0).toUpperCase()+s.slice(1):''; }
        
        function clearAll() {
            document.querySelectorAll('select').forEach(s => s.value = '');
            document.querySelectorAll('input').forEach(i => i.value = '');
            document.querySelectorAll('.dynamic-params').forEach(d => d.classList.remove('visible'));
            document.getElementById('algorithm-params-content').innerHTML = '';
            document.getElementById('model-params-content').innerHTML = '';
            document.getElementById('state-params-content').innerHTML = '';
            document.getElementById('state-name-container').style.display = 'none';
            updateCommand();
        }
        
        function copyCommand() {
            navigator.clipboard.writeText(document.getElementById('output-command').textContent).then(() => {
                const toast = document.getElementById('toast');
                toast.style.display = 'block';
                setTimeout(() => toast.style.display = 'none', 2000);
            });
        }
        
        window.onload = initialize;
    </script>
</body>
</html>
"""
end