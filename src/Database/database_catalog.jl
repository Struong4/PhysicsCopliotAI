# ============================================================================
# CATALOG MANAGEMENT FOR TENSOR NETWORK SIMULATIONS
# ============================================================================
#
# This module provides a queryable catalog of simulation runs.
# Complements runs_index.json (identity) with discovery capabilities.
#
# ARCHITECTURE:
#   - runs_index.json: Hash → run_id (exact match, deduplication)
#   - run_catalog.jsonl: Queryable metadata (discovery, filtering)
#   - config.json: Source of truth (reconstruction)
#
# SCHEMA:
# {
#   "run_id": "...",
#   "config_hash": "...",
#   "timestamp": "...",
#   "status": "completed",
#
#   "core": { algorithm, system_type, N, S, dtype },
#
#   "algorithm_params": { ... },
#
#   "model": {
#     "kind": "prebuilt" | "custom",
#     "name": "...",
#     "params": { ... }           # prebuilt
#     # "channels": [...],        # custom (future)
#     # "facets": { ... }         # custom (future)
#   },
#
#   "state": {
#     "kind": "prebuilt" | "custom" | "random",
#     "name": "...",
#     "params": { ... }
#   },
#
#   "results_summary": { ... }
# }
#
# FILE FORMAT: JSON Lines (.jsonl) - one JSON object per line
#
# USAGE:
#   Write: _append_to_catalog(config, run_id, status, results; base_dir)
#   Read:  _load_catalog(; base_dir)
#
# ============================================================================

using JSON
using Dates

# ============================================================================
# PART 1: CORE EXTRACTION
# ============================================================================

"""
    _extract_core(config) -> Dict

Extract universal fields that exist for every simulation.
These fields are stable across all algorithms and models.
"""
function _extract_core(config::Dict)
    system = config["system"]
    algorithm = config["algorithm"]
    
    core = Dict{String, Any}(
        "algorithm" => algorithm["type"],
        "system_type" => system["type"],
        "S" => get(system, "S", 0.5),
        "dtype" => get(system, "dtype", "ComplexF64")
    )
    
    # N depends on system type
    if system["type"] == "spin"
        core["N"] = system["N"]
    elseif system["type"] == "spinboson"
        core["N_spins"] = system["N_spins"]
        core["nmax"] = system["nmax"]
    end
    
    return core
end

# ============================================================================
# PART 2: ALGORITHM PARAMS EXTRACTION
# ============================================================================

"""
    _extract_algorithm_params(config) -> Dict

Extract algorithm-specific parameters.
Designed to be extensible for new algorithms.
"""
function _extract_algorithm_params(config::Dict)
    algorithm = config["algorithm"]
    algo_type = algorithm["type"]
    
    # Dispatch to algorithm-specific extractor
    if algo_type == "dmrg"
        return _extract_dmrg_params(algorithm)
    elseif algo_type == "tdvp"
        return _extract_tdvp_params(algorithm)
    else
        # Fallback for future algorithms: extract what we can
        return _extract_generic_algorithm_params(algorithm)
    end
end

"""
Extract DMRG-specific parameters.
"""
function _extract_dmrg_params(algorithm::Dict)
    params = Dict{String, Any}()
    
    # Solver
    if haskey(algorithm, "solver")
        solver = algorithm["solver"]
        params["solver"] = solver["type"]
        if haskey(solver, "krylov_dim")
            params["krylov_dim"] = solver["krylov_dim"]
        end
        if haskey(solver, "max_iter")
            params["max_iter"] = solver["max_iter"]
        end
    end
    
    # Options
    if haskey(algorithm, "options")
        opts = algorithm["options"]
        if haskey(opts, "chi_max")
            params["chi_max"] = opts["chi_max"]
        end
        if haskey(opts, "cutoff")
            params["cutoff"] = opts["cutoff"]
        end
    end
    
    # Run
    if haskey(algorithm, "run")
        params["n_sweeps"] = algorithm["run"]["n_sweeps"]
    end
    
    return params
end

"""
Extract TDVP-specific parameters.
"""
function _extract_tdvp_params(algorithm::Dict)
    params = Dict{String, Any}()
    
    # Solver
    if haskey(algorithm, "solver")
        solver = algorithm["solver"]
        params["solver"] = solver["type"]
        if haskey(solver, "krylov_dim")
            params["krylov_dim"] = solver["krylov_dim"]
        end
        if haskey(solver, "tol")
            params["tol"] = solver["tol"]
        end
        if haskey(solver, "evol_type")
            params["evol_type"] = solver["evol_type"]
        end
    end
    
    # Options
    if haskey(algorithm, "options")
        opts = algorithm["options"]
        if haskey(opts, "dt")
            params["dt"] = opts["dt"]
        end
        if haskey(opts, "chi_max")
            params["chi_max"] = opts["chi_max"]
        end
        if haskey(opts, "cutoff")
            params["cutoff"] = opts["cutoff"]
        end
    end
    
    # Run
    if haskey(algorithm, "run")
        params["n_sweeps"] = algorithm["run"]["n_sweeps"]
    end
    
    return params
end

"""
Generic fallback for unknown algorithms.
Extracts common fields without assuming structure.
"""
function _extract_generic_algorithm_params(algorithm::Dict)
    params = Dict{String, Any}()
    
    if haskey(algorithm, "solver") && haskey(algorithm["solver"], "type")
        params["solver"] = algorithm["solver"]["type"]
    end
    
    if haskey(algorithm, "options")
        opts = algorithm["options"]
        for key in ["chi_max", "cutoff", "dt"]
            if haskey(opts, key)
                params[key] = opts[key]
            end
        end
    end
    
    if haskey(algorithm, "run") && haskey(algorithm["run"], "n_sweeps")
        params["n_sweeps"] = algorithm["run"]["n_sweeps"]
    end
    
    return params
end

# ============================================================================
# PART 3: MODEL EXTRACTION
# ============================================================================

"""
    _extract_model(config) -> Dict

Extract model information.
Returns structured dict with kind, name, and params/channels/facets.
"""
function _extract_model(config::Dict)
    model = config["model"]
    model_name = model["name"]
    
    # Determine kind
    if model_name in ["custom_spin", "custom_spinboson"]
        return _extract_custom_model(model)
    else
        return _extract_prebuilt_model(model)
    end
end

"""
Extract prebuilt model parameters.
Each model has a known, fixed set of parameters.
"""
function _extract_prebuilt_model(model::Dict)
    model_name = model["name"]
    model_params = model["params"]
    
    result = Dict{String, Any}(
        "kind" => "prebuilt",
        "name" => model_name,
        "params" => Dict{String, Any}()
    )
    
    params = result["params"]
    
    if model_name == "transverse_field_ising"
        params["J"] = model_params["J"]
        params["h"] = model_params["h"]
        params["coupling_dir"] = model_params["coupling_dir"]
        params["field_dir"] = model_params["field_dir"]
        
    elseif model_name == "heisenberg"
        params["Jx"] = model_params["Jx"]
        params["Jy"] = model_params["Jy"]
        params["Jz"] = model_params["Jz"]
        params["hx"] = model_params["hx"]
        params["hy"] = model_params["hy"]
        params["hz"] = model_params["hz"]
        
    elseif model_name == "long_range_ising"
        params["J"] = model_params["J"]
        params["h"] = model_params["h"]
        params["alpha"] = model_params["alpha"]
        params["n_exp"] = model_params["n_exp"]
        params["coupling_dir"] = model_params["coupling_dir"]
        params["field_dir"] = model_params["field_dir"]
        
    elseif model_name == "ising_dickie"
        params["J"] = model_params["J"]
        params["h"] = model_params["h"]
        params["omega"] = model_params["omega"]
        params["g"] = model_params["g"]
        params["spin_coupling_dir"] = model_params["spin_coupling_dir"]
        params["spin_field_dir"] = model_params["spin_field_dir"]
        params["boson_coupling_dir"] = model_params["boson_coupling_dir"]
        
    elseif model_name == "long_range_ising_dickie"
        params["J"] = model_params["J"]
        params["h"] = model_params["h"]
        params["alpha"] = model_params["alpha"]
        params["n_exp"] = model_params["n_exp"]
        params["omega"] = model_params["omega"]
        params["g"] = model_params["g"]
        params["spin_coupling_dir"] = model_params["spin_coupling_dir"]
        params["spin_field_dir"] = model_params["spin_field_dir"]
        params["boson_coupling_dir"] = model_params["boson_coupling_dir"]
        
    else
        # Unknown prebuilt model: store all params as-is
        @warn "Unknown prebuilt model: $model_name. Storing raw params."
        for (k, v) in model_params
            params[k] = v
        end
    end
    
    return result
end

"""
Extract custom model (placeholder for future implementation).
Currently stores only kind and name.
"""
function _extract_custom_model(model::Dict)
    # TODO: Implement channels and facets extraction
    return Dict{String, Any}(
        "kind" => "custom",
        "name" => model["name"]
        # Future: "channels" => [...],
        # Future: "facets" => {...}
    )
end

# ============================================================================
# PART 4: STATE EXTRACTION
# ============================================================================

"""
    _extract_state(config) -> Dict

Extract state information.
Returns structured dict with kind, name, and params.
"""
function _extract_state(config::Dict)
    state = config["state"]
    state_type = state["type"]
    
    if state_type == "random"
        return _extract_random_state(state)
    elseif state_type == "custom"
        return _extract_custom_state(state)
    elseif state_type == "prebuilt"
        return _extract_prebuilt_state(state)
    else
        @warn "Unknown state type: $state_type"
        return Dict{String, Any}("kind" => state_type)
    end
end

"""
Extract random state parameters.
"""
function _extract_random_state(state::Dict)
    result = Dict{String, Any}(
        "kind" => "random",
        "params" => Dict{String, Any}()
    )
    
    if haskey(state, "params") && haskey(state["params"], "bond_dim")
        result["params"]["bond_dim"] = state["params"]["bond_dim"]
    end
    
    return result
end

"""
Extract custom state (placeholder for future implementation).
"""
function _extract_custom_state(state::Dict)
    # TODO: Implement custom state extraction
    return Dict{String, Any}(
        "kind" => "custom"
        # Future: full specification
    )
end

"""
Extract prebuilt state parameters.
"""
function _extract_prebuilt_state(state::Dict)
    state_name = state["name"]
    state_params = get(state, "params", Dict())
    
    result = Dict{String, Any}(
        "kind" => "prebuilt",
        "name" => state_name,
        "params" => Dict{String, Any}()
    )
    
    params = result["params"]
    
    # Common parameter
    if haskey(state_params, "spin_direction")
        params["spin_direction"] = state_params["spin_direction"]
    end
    
    # Boson level (for spin-boson systems)
    if haskey(state_params, "boson_level")
        params["boson_level"] = state_params["boson_level"]
    end
    
    if state_name == "polarized"
        if haskey(state_params, "eigenstate")
            params["eigenstate"] = state_params["eigenstate"]
        end
        if haskey(state_params, "spin_eigenstate")
            params["spin_eigenstate"] = state_params["spin_eigenstate"]
        end
        
    elseif state_name == "neel"
        if haskey(state_params, "even_state")
            params["even_state"] = state_params["even_state"]
        end
        if haskey(state_params, "odd_state")
            params["odd_state"] = state_params["odd_state"]
        end
        
    elseif state_name == "kink"
        if haskey(state_params, "position")
            params["position"] = state_params["position"]
        end
        if haskey(state_params, "left_state")
            params["left_state"] = state_params["left_state"]
        end
        if haskey(state_params, "right_state")
            params["right_state"] = state_params["right_state"]
        end
        
    elseif state_name == "domain"
        if haskey(state_params, "start_index")
            params["start_index"] = state_params["start_index"]
        end
        if haskey(state_params, "domain_size")
            params["domain_size"] = state_params["domain_size"]
        end
        if haskey(state_params, "base_state")
            params["base_state"] = state_params["base_state"]
        end
        if haskey(state_params, "flip_state")
            params["flip_state"] = state_params["flip_state"]
        end
        
    else
        # Unknown prebuilt state: store all params as-is
        @warn "Unknown prebuilt state: $state_name. Storing raw params."
        for (k, v) in state_params
            params[k] = v
        end
    end
    
    return result
end

# ============================================================================
# PART 5: RESULTS SUMMARY EXTRACTION
# ============================================================================

"""
    _extract_results_summary(config, run_dir) -> Dict

Extract summary of simulation results from metadata.
Called after simulation completes.
"""
function _extract_results_summary(config::Dict, run_dir::String)
    summary = Dict{String, Any}()
    
    # Load metadata if available
    metadata_path = joinpath(run_dir, "metadata.json")
    if isfile(metadata_path)
        metadata = JSON.parsefile(metadata_path)
        
        if haskey(metadata, "sweeps_completed")
            summary["sweeps_completed"] = metadata["sweeps_completed"]
        end
        
        # Algorithm-specific summaries
        algo_type = config["algorithm"]["type"]
        
        if algo_type == "tdvp" && haskey(metadata, "dt")
            # Compute final time
            if haskey(metadata, "sweeps_completed")
                summary["final_time"] = metadata["sweeps_completed"] * metadata["dt"]
            end
        end
        
        # Extract from sweep_data if available
        if haskey(metadata, "sweep_data") && !isempty(metadata["sweep_data"])
            last_sweep = metadata["sweep_data"][end]
            
            if haskey(last_sweep, "energy")
                summary["final_energy"] = last_sweep["energy"]
            end
            if haskey(last_sweep, "max_bond_dim")
                summary["final_max_bond_dim"] = last_sweep["max_bond_dim"]
            end
            if haskey(last_sweep, "time")
                summary["final_time"] = last_sweep["time"]
            end
        end
    end
    
    return summary
end

# ============================================================================
# PART 6: MAIN ENTRY POINT
# ============================================================================

"""
    _extract_catalog_entry(config, run_id, status, run_dir) -> Dict

Extract full catalog entry from simulation config and results.

# Arguments
- `config::Dict`: Full simulation configuration
- `run_id::String`: Unique run identifier
- `status::String`: Run status ("completed", "failed", etc.)
- `run_dir::String`: Path to run directory (for results extraction)

# Returns
- Dict: Complete catalog entry ready for storage
"""
function _extract_catalog_entry(config::Dict, run_id::String, status::String, 
                                run_dir::String)
    # Compute config hash (reuse from database_utils.jl)
    config_hash = _compute_config_hash(config)
    
    return Dict{String, Any}(
        "run_id" => run_id,
        "config_hash" => config_hash,
        "timestamp" => Dates.format(now(), "yyyy-mm-ddTHH:MM:SS"),
        "status" => status,
        "core" => _extract_core(config),
        "algorithm_params" => _extract_algorithm_params(config),
        "model" => _extract_model(config),
        "state" => _extract_state(config),
        "results_summary" => _extract_results_summary(config, run_dir)
    )
end

# ============================================================================
# PART 7: CATALOG I/O
# ============================================================================

const CATALOG_FILENAME = "run_catalog.jsonl"

"""
    _append_to_catalog(config, run_id, status, run_dir; base_dir="data")

Append a catalog entry for a completed simulation run.
Creates catalog file if it doesn't exist.

# Arguments
- `config::Dict`: Full simulation configuration
- `run_id::String`: Unique run identifier
- `status::String`: Run status
- `run_dir::String`: Path to run directory
- `base_dir::String`: Base data directory (default: "data")

# Returns
- Dict: The catalog entry that was appended
"""
function _append_to_catalog(config::Dict, run_id::String, status::String, 
                            run_dir::String; base_dir::String="data")
    # Extract catalog entry
    entry = _extract_catalog_entry(config, run_id, status, run_dir)
    
    # Ensure base directory exists
    mkpath(base_dir)
    
    # Append to jsonl file
    catalog_path = joinpath(base_dir, CATALOG_FILENAME)
    open(catalog_path, "a") do f
        JSON.print(f, entry)
        println(f)  # newline after each entry
    end
    
    println("  ✓ Appended to catalog: $run_id")
    
    return entry
end

"""
    _load_catalog(; base_dir="data") -> Vector{Dict}

Load all catalog entries from jsonl file.
Returns empty vector if catalog doesn't exist.
"""
function _load_catalog(; base_dir::String="data")
    catalog_path = joinpath(base_dir, CATALOG_FILENAME)
    
    if !isfile(catalog_path)
        return Dict{String, Any}[]
    end
    
    entries = Dict{String, Any}[]
    
    open(catalog_path, "r") do f
        for line in eachline(f)
            stripped = strip(line)
            if !isempty(stripped)
                entry = JSON.parse(stripped)
                push!(entries, entry)
            end
        end
    end
    
    return entries
end

"""
    _catalog_exists(; base_dir="data") -> Bool

Check if catalog file exists.
"""
function _catalog_exists(; base_dir::String="data")
    return isfile(joinpath(base_dir, CATALOG_FILENAME))
end

"""
    _catalog_count(; base_dir="data") -> Int

Count entries in catalog without loading all into memory.
"""
function _catalog_count(; base_dir::String="data")
    catalog_path = joinpath(base_dir, CATALOG_FILENAME)
    
    if !isfile(catalog_path)
        return 0
    end
    
    count = 0
    open(catalog_path, "r") do f
        for line in eachline(f)
            if !isempty(strip(line))
                count += 1
            end
        end
    end
    
    return count
end