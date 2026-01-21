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
#   
#   # Get paths for selected runs
#   for r in results
#       config = load_config(r)
#       # ... use for observable calculation
#   end
#
# FILTER TYPES:
#   - Exact match: algorithm="tdvp", model_name="heisenberg"
#   - Comparison: N_gte=50, N_lte=100, model_J_gt=1.0
#   - Status: status="completed"
#
# ============================================================================

using JSON

# ============================================================================
# PART 1: QUERY FUNCTION
# ============================================================================

"""
    query_catalog(; base_dir="data", filters...) -> Vector{Dict}

Query the catalog for runs matching specified filters.

# Filter Syntax
- Core fields: `algorithm`, `system_type`, `N`, `S`, `dtype`, `status`
- Algorithm params: `chi_max`, `dt`, `n_sweeps`, `solver`, etc.
- Model: `model_name`, `model_kind`, `model_<param>` (e.g., `model_J`, `model_alpha`)
- State: `state_name`, `state_kind`, `state_<param>` (e.g., `state_spin_direction`)

# Comparison Operators
Append suffix to field name:
- `_gt`: greater than
- `_gte`: greater than or equal
- `_lt`: less than
- `_lte`: less than or equal

# Returns
Vector of matching catalog entries. Each entry contains full metadata
plus computed `run_dir` path.

# Examples
```julia
# All TDVP runs
results = query_catalog(algorithm="tdvp")

# DMRG runs with N >= 50
results = query_catalog(algorithm="dmrg", N_gte=50)

# Long-range Ising with alpha < 2.0
results = query_catalog(model_name="long_range_ising", model_alpha_lt=2.0)

# Completed runs only
results = query_catalog(status="completed")
```
"""
function query_catalog(; base_dir::String="data", filters...)
    # Load catalog
    entries = _load_catalog(base_dir=base_dir)
    
    if isempty(entries)
        println("Catalog is empty.")
        return Dict{String, Any}[]
    end
    
    # Apply filters
    results = Dict{String, Any}[]
    
    for entry in entries
        if _matches_filters(entry, filters)
            # Add computed run_dir
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

"""
    _matches_filters(entry, filters) -> Bool

Check if a catalog entry matches all specified filters.
"""
function _matches_filters(entry::Dict, filters)
    for (key, value) in filters
        if !_matches_single_filter(entry, key, value)
            return false
        end
    end
    return true
end

"""
    _matches_single_filter(entry, key, value) -> Bool

Check if entry matches a single filter criterion.
Handles field lookup and comparison operators.
"""
function _matches_single_filter(entry::Dict, key::Symbol, value)
    key_str = String(key)
    
    # Parse comparison operator
    op, field_name = _parse_filter_key(key_str)
    
    # Get field value from entry
    field_value = _get_field_value(entry, field_name)
    
    # Field not found
    if field_value === nothing
        return false
    end
    
    # Apply comparison
    return _compare(field_value, op, value)
end

"""
    _parse_filter_key(key) -> (operator, field_name)

Parse filter key to extract comparison operator and field name.

Examples:
- "N_gte" -> (:gte, "N")
- "model_J_lt" -> (:lt, "model_J")
- "algorithm" -> (:eq, "algorithm")
"""
function _parse_filter_key(key::String)
    # Check for comparison suffixes
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
- "algorithm" -> entry["core"]["algorithm"]
- "N" -> entry["core"]["N"]
- "status" -> entry["status"]
- "chi_max" -> entry["algorithm_params"]["chi_max"]
- "model_name" -> entry["model"]["name"]
- "model_J" -> entry["model"]["params"]["J"]
- "state_name" -> entry["state"]["name"]
- "state_spin_direction" -> entry["state"]["params"]["spin_direction"]
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
    
    # Algorithm params
    if field_name in ["chi_max", "cutoff", "dt", "n_sweeps", "solver", 
                      "krylov_dim", "max_iter", "tol", "evol_type"]
        return get(entry["algorithm_params"], field_name, nothing)
    end
    
    # Model fields
    if startswith(field_name, "model_")
        return _get_model_field(entry, field_name[7:end])  # Remove "model_" prefix
    end
    
    # State fields
    if startswith(field_name, "state_")
        return _get_state_field(entry, field_name[7:end])  # Remove "state_" prefix
    end
    
    # Results summary
    if startswith(field_name, "result_")
        result_field = field_name[8:end]  # Remove "result_" prefix
        return get(get(entry, "results_summary", Dict()), result_field, nothing)
    end
    
    return nothing
end

"""
Extract model field value.
"""
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
    
    # Model params (for prebuilt)
    params = get(model, "params", nothing)
    if params !== nothing
        return get(params, field_name, nothing)
    end
    
    return nothing
end

"""
Extract state field value.
"""
function _get_state_field(entry::Dict, field_name::String)
    state = get(entry, "state", nothing)
    if state === nothing
        return nothing
    end
    
    # Direct state fields
    if field_name == "name"
        return get(state, "name", nothing)
    elseif field_name == "kind"
        return get(state, "kind", nothing)
    end
    
    # State params
    params = get(state, "params", nothing)
    if params !== nothing
        return get(params, field_name, nothing)
    end
    
    return nothing
end

"""
    _compare(field_value, op, filter_value) -> Bool

Apply comparison operator.
"""
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

"""
    _compute_run_dir(entry, base_dir) -> String

Compute run directory path from catalog entry.
"""
function _compute_run_dir(entry::Dict, base_dir::String)
    algorithm = entry["core"]["algorithm"]
    run_id = entry["run_id"]
    return joinpath(base_dir, algorithm, run_id)
end

# ============================================================================
# PART 4: DISPLAY FUNCTIONS
# ============================================================================

"""
    display_results(results; max_rows=20)

Pretty print query results as a table.
"""
function display_results(results::Vector{Dict{String, Any}}; max_rows::Int=20)
    if isempty(results)
        println("No matching runs found.")
        return
    end
    
    n_results = length(results)
    println("\n", "="^70)
    println("Found $n_results matching run(s)")
    println("="^70)
    
    # Determine display count
    display_count = min(n_results, max_rows)
    
    for (i, entry) in enumerate(results[1:display_count])
        _display_single_result(entry, i)
    end
    
    if n_results > max_rows
        println("\n... and $(n_results - max_rows) more results (use max_rows to show more)")
    end
    
    println("="^70)
end

"""
Display a single result entry.
"""
function _display_single_result(entry::Dict, index::Int)
    println("\n[$index] $(entry["run_id"])")
    println("    Status: $(entry["status"])")
    println("    Algorithm: $(entry["core"]["algorithm"])")
    
    # System info
    core = entry["core"]
    if haskey(core, "N")
        println("    System: $(core["system_type"]), N=$(core["N"]), S=$(core["S"])")
    else
        println("    System: $(core["system_type"]), N_spins=$(core["N_spins"]), nmax=$(core["nmax"]), S=$(core["S"])")
    end
    
    # Model info
    model = entry["model"]
    print("    Model: $(model["name"])")
    if model["kind"] == "prebuilt" && haskey(model, "params")
        params_str = join(["$k=$v" for (k, v) in model["params"]], ", ")
        print(" ($params_str)")
    end
    println()
    
    # State info
    state = entry["state"]
    print("    State: $(get(state, "name", state["kind"]))")
    if haskey(state, "params") && !isempty(state["params"])
        params_str = join(["$k=$v" for (k, v) in state["params"]], ", ")
        print(" ($params_str)")
    end
    println()
    
    # Results summary
    if haskey(entry, "results_summary") && !isempty(entry["results_summary"])
        summary = entry["results_summary"]
        print("    Results: ")
        summary_str = join(["$k=$v" for (k, v) in summary], ", ")
        println(summary_str)
    end
    
    # Path
    println("    Path: $(entry["run_dir"])")
end

"""
    display_results_compact(results)

Display results as a compact table (one line per result).
"""
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
        state = get(entry["state"], "name", entry["state"]["kind"])
        
        @printf("%-28s %-10s %-8s %-6s %-20s %-15s\n",
                run_id, status, algo, N, model, state)
    end
    
    println("-"^100)
    println("Total: $(length(results)) run(s)")
end

# ============================================================================
# PART 5: CONVENIENCE FUNCTIONS
# ============================================================================

"""
    get_run_ids(results) -> Vector{String}

Extract run_ids from query results.
"""
function get_run_ids(results::Vector{Dict{String, Any}})
    return [r["run_id"] for r in results]
end

"""
    get_run_dirs(results) -> Vector{String}

Extract run directories from query results.
"""
function get_run_dirs(results::Vector{Dict{String, Any}})
    return [r["run_dir"] for r in results]
end

"""
    load_config(result; base_dir="data") -> Dict

Load the full config.json for a query result.
This is the source of truth for reconstruction.
"""
function load_config(result::Dict; base_dir::String="data")
    run_dir = get(result, "run_dir", nothing)
    
    if run_dir === nothing
        # Compute if not present
        run_dir = _compute_run_dir(result, base_dir)
    end
    
    config_path = joinpath(run_dir, "config.json")
    
    if !isfile(config_path)
        error("Config file not found: $config_path")
    end
    
    return JSON.parsefile(config_path)
end

"""
    list_available_models(; base_dir="data") -> Vector{String}

List all unique model names in the catalog.
"""
function list_available_models(; base_dir::String="data")
    entries = _load_catalog(base_dir=base_dir)
    models = Set{String}()
    
    for entry in entries
        push!(models, entry["model"]["name"])
    end
    
    return sort(collect(models))
end

"""
    list_available_algorithms(; base_dir="data") -> Vector{String}

List all unique algorithms in the catalog.
"""
function list_available_algorithms(; base_dir::String="data")
    entries = _load_catalog(base_dir=base_dir)
    algorithms = Set{String}()
    
    for entry in entries
        push!(algorithms, entry["core"]["algorithm"])
    end
    
    return sort(collect(algorithms))
end

"""
    catalog_summary(; base_dir="data")

Print a summary of the catalog contents.
"""
function catalog_summary(; base_dir::String="data")
    entries = _load_catalog(base_dir=base_dir)
    
    if isempty(entries)
        println("Catalog is empty.")
        return
    end
    
    # Count by status
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