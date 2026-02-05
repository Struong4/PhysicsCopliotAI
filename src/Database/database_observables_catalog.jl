# ============================================================================
# CATALOG MANAGEMENT FOR OBSERVABLE CALCULATIONS (TN + ED)
# ============================================================================
#
# This module provides a queryable catalog of observable calculation runs.
# Complements observables_index.json (identity) with discovery capabilities.
#
# ARCHITECTURE:
#   - observables_index.json: Hash → obs_run_id (exact match, deduplication)
#   - observables_catalog.jsonl: Queryable metadata (discovery, filtering)
#   - observable_config.json: Source of truth (reconstruction)
#
# DESIGN PHILOSOPHY:
#   Observable catalog is INDEPENDENT and SELF-CONTAINED.
#   It stores COMPLETE simulation parameters (extracted from config["simulation"])
#   so that observables can be queried WITHOUT accessing simulation catalog.
#
# SUPPORTED ALGORITHMS:
#   TN: dmrg, tdvp
#   ED: ed_spectrum, ed_time_evolution
#
# SCHEMA:
# {
#   "obs_run_id": "...",
#   "sim_run_id": "...",
#   "obs_config_hash": "...",
#   "timestamp": "...",
#   "status": "completed",
#
#   "simulation": {
#     "core": { algorithm, system_type, N, S, dtype },
#     "algorithm_params": { ... },
#     "model": { kind, name, params },
#     "state": { kind, name, params }
#   },
#
#   "observable": {
#     "type": "correlation_function",
#     "params": { ... }
#   },
#
#   "analysis_params": {
#     "sweep_selection" | "step_selection" | "state_selection": { ... }
#   },
#
#   "results_summary": {
#     "n_sweeps_analyzed": 50,
#     "computation_time_sec": 12.5
#   }
# }
#
# FILE FORMAT: JSON Lines (.jsonl) - one JSON object per line
#
# USAGE:
#   Write: _append_to_observables_catalog(config, obs_run_id, sim_run_id, status, obs_run_dir; obs_base_dir)
#   Read:  _load_observables_catalog(; obs_base_dir)
#
# ============================================================================

using JSON
using Dates

# ============================================================================
# PART 1: SIMULATION INFO EXTRACTION (Reuses database_catalog.jl functions)
# ============================================================================

"""
    _extract_simulation_info_for_observable(config) -> Dict

Extract COMPLETE simulation information from observable config.
Reuses ALL extraction functions from database_catalog.jl for consistency.

The observable config has structure:
{
  "simulation": { system, model, state, algorithm },
  "analysis": { ... }
}

We extract from config["simulation"] using the same functions that
extract from simulation configs directly.
"""
function _extract_simulation_info_for_observable(config::Dict)
    # Extract from the embedded simulation config
    sim_config = config["simulation"]
    
    # Reuse all the detailed extraction functions from database_catalog.jl
    # These handle ALL the complexity: prebuilt models, custom models, states, etc.
    result = Dict{String, Any}(
        "core" => _extract_core(sim_config),
        "algorithm_params" => _extract_algorithm_params(sim_config),
        "model" => _extract_model(sim_config)
    )
    
    # Only extract state if present (ed_spectrum doesn't have initial state)
    if haskey(sim_config, "state")
        result["state"] = _extract_state(sim_config)
    end
    
    return result
end

# ============================================================================
# PART 2: OBSERVABLE EXTRACTION
# ============================================================================

"""
    _extract_observable_info(config) -> Dict

Extract observable type and parameters from analysis config.
"""
function _extract_observable_info(config::Dict)
    obs = config["analysis"]["observable"]
    
    result = Dict{String, Any}(
        "type" => obs["type"]
    )
    
    # Extract parameters based on observable type
    if haskey(obs, "params")
        result["params"] = _extract_observable_params(obs["type"], obs["params"])
    else
        result["params"] = Dict{String, Any}()
    end
    
    return result
end

"""
    _extract_observable_params(obs_type, params) -> Dict

Extract observable-specific parameters.
Handles all 9 observable types with appropriate parameter extraction.
"""
function _extract_observable_params(obs_type::String, params::Dict)
    result = Dict{String, Any}()
    
    if obs_type == "single_site_expectation"
        result["site"] = params["site"]
        result["operator"] = params["operator"]
        
    elseif obs_type == "subsystem_expectation_sum"
        result["operator"] = params["operator"]
        result["l"] = params["l"]
        result["m"] = params["m"]
        
    elseif obs_type == "two_site_expectation"
        result["site_i"] = params["site_i"]
        result["site_j"] = params["site_j"]
        result["operator_i"] = params["operator_i"]
        result["operator_j"] = params["operator_j"]
        
    elseif obs_type == "correlation_function"
        result["site_i"] = params["site_i"]
        result["site_j"] = params["site_j"]
        result["operator"] = params["operator"]
        
    elseif obs_type == "connected_correlation"
        result["site_i"] = params["site_i"]
        result["site_j"] = params["site_j"]
        result["operator"] = params["operator"]
        
    elseif obs_type == "entanglement_entropy"
        result["bond"] = params["bond"]
        if haskey(params, "alpha")
            result["alpha"] = params["alpha"]
        end
        
    elseif obs_type == "entanglement_spectrum"
        result["bond"] = params["bond"]
        if haskey(params, "n_values")
            result["n_values"] = params["n_values"]
        end
        
    elseif obs_type == "energy_expectation"
        # No params for energy expectation
        
    elseif obs_type == "energy_variance"
        # No params for energy variance
        
    else
        # Unknown observable type: store all params as-is
        @warn "Unknown observable type: $obs_type. Storing raw params."
        for (k, v) in params
            result[k] = v
        end
    end
    
    return result
end

# ============================================================================
# PART 3: ANALYSIS PARAMS EXTRACTION
# ============================================================================

"""
    _extract_analysis_params(config) -> Dict

Extract analysis configuration (which sweeps/steps/states to analyze).
Different structure for TN vs ED algorithms.
"""
function _extract_analysis_params(config::Dict)
    analysis = config["analysis"]
    sim_algorithm = config["simulation"]["algorithm"]["type"]
    
    params = Dict{String, Any}()
    
    # ────────────────────────────────────────────────────────────────────────
    # TN Algorithms: sweep selection
    # ────────────────────────────────────────────────────────────────────────
    if sim_algorithm in ["dmrg", "tdvp"]
        if haskey(analysis, "sweeps")
            params["sweep_selection"] = _extract_selection(analysis["sweeps"])
        end
    
    # ────────────────────────────────────────────────────────────────────────
    # ED Spectrum: state selection
    # ────────────────────────────────────────────────────────────────────────
    elseif sim_algorithm == "ed_spectrum"
        if haskey(analysis, "states")
            params["state_selection"] = _extract_selection(analysis["states"])
        end
    
    # ────────────────────────────────────────────────────────────────────────
    # ED Time Evolution: step selection
    # ────────────────────────────────────────────────────────────────────────
    elseif sim_algorithm == "ed_time_evolution"
        if haskey(analysis, "steps")
            params["step_selection"] = _extract_selection(analysis["steps"])
        end
    end
    
    return params
end

"""
    _extract_selection(selection_config) -> Dict

Extract selection specification (all, range, specific, time_range, ground).
"""
function _extract_selection(selection_config::Dict)
    result = Dict{String, Any}(
        "type" => selection_config["selection"]
    )
    
    sel_type = selection_config["selection"]
    
    if sel_type == "range" && haskey(selection_config, "range")
        result["range"] = selection_config["range"]
    elseif sel_type == "specific" && haskey(selection_config, "list")
        result["list"] = selection_config["list"]
    elseif sel_type == "time_range" && haskey(selection_config, "time_range")
        result["time_range"] = selection_config["time_range"]
    end
    
    return result
end

# ============================================================================
# PART 4: RESULTS SUMMARY EXTRACTION
# ============================================================================

"""
    _extract_observable_results_summary(config, obs_run_dir) -> Dict

Extract summary of observable calculation results from metadata.
Called after calculation completes.
"""
function _extract_observable_results_summary(config::Dict, obs_run_dir::String)
    summary = Dict{String, Any}()
    
    # Load metadata if available
    metadata_path = joinpath(obs_run_dir, "metadata.json")
    if !isfile(metadata_path)
        return summary
    end
    
    metadata = JSON.parsefile(metadata_path)
    sim_algorithm = config["simulation"]["algorithm"]["type"]
    
    # ────────────────────────────────────────────────────────────────────────
    # Common fields
    # ────────────────────────────────────────────────────────────────────────
    if haskey(metadata, "sweeps_processed")
        summary["n_sweeps_analyzed"] = metadata["sweeps_processed"]
    end
    
    if haskey(metadata, "steps_processed")
        summary["n_steps_analyzed"] = metadata["steps_processed"]
    end
    
    if haskey(metadata, "states_processed")
        summary["n_states_analyzed"] = metadata["states_processed"]
    end
    
    # ────────────────────────────────────────────────────────────────────────
    # Timing information
    # ────────────────────────────────────────────────────────────────────────
    if haskey(metadata, "start_time") && haskey(metadata, "end_time")
        try
            start_time = DateTime(metadata["start_time"])
            end_time = DateTime(metadata["end_time"])
            duration = Dates.value(end_time - start_time) / 1000.0  # Convert to seconds
            summary["computation_time_sec"] = duration
        catch
            # If parsing fails, skip timing info
        end
    end
    
    return summary
end

# ============================================================================
# PART 5: MAIN ENTRY POINT
# ============================================================================

"""
    _extract_observable_catalog_entry(config, obs_run_id, sim_run_id, status, obs_run_dir) -> Dict

Extract full catalog entry from observable config and results.

# Arguments
- `config::Dict`: Full analysis configuration (with "simulation" and "analysis")
- `obs_run_id::String`: Unique observable run identifier
- `sim_run_id::String`: Simulation run identifier (links to data)
- `status::String`: Run status ("completed", "failed", etc.)
- `obs_run_dir::String`: Path to observable run directory

# Returns
- Dict: Complete catalog entry ready for storage

# Note
This function reuses ALL simulation extraction logic from database_catalog.jl
to ensure the observable catalog has COMPLETE simulation information.
"""
function _extract_observable_catalog_entry(config::Dict, obs_run_id::String, 
                                           sim_run_id::String, status::String,
                                           obs_run_dir::String)
    # Compute observable config hash (reuse from database_observables_utils.jl)
    obs_config_hash = _compute_observable_config_hash(config)
    
    return Dict{String, Any}(
        "obs_run_id" => obs_run_id,
        "sim_run_id" => sim_run_id,
        "obs_config_hash" => obs_config_hash,
        "timestamp" => Dates.format(now(), "yyyy-mm-ddTHH:MM:SS"),
        "status" => status,
        "simulation" => _extract_simulation_info_for_observable(config),
        "observable" => _extract_observable_info(config),
        "analysis_params" => _extract_analysis_params(config),
        "results_summary" => _extract_observable_results_summary(config, obs_run_dir)
    )
end

# ============================================================================
# PART 6: CATALOG I/O
# ============================================================================

const OBSERVABLES_CATALOG_FILENAME = "observables_catalog.jsonl"

"""
    _append_to_observables_catalog(config, obs_run_id, sim_run_id, status, obs_run_dir; obs_base_dir="observables")

Append a catalog entry for a completed observable calculation.
Creates catalog file if it doesn't exist.

# Arguments
- `config::Dict`: Full analysis configuration
- `obs_run_id::String`: Unique observable run identifier
- `sim_run_id::String`: Simulation run identifier
- `status::String`: Run status
- `obs_run_dir::String`: Path to observable run directory
- `obs_base_dir::String`: Base observable directory (default: "observables")

# Returns
- Dict: The catalog entry that was appended
"""
function _append_to_observables_catalog(config::Dict, obs_run_id::String,
                                        sim_run_id::String, status::String,
                                        obs_run_dir::String; 
                                        obs_base_dir::String="observables")
    # Extract catalog entry
    entry = _extract_observable_catalog_entry(config, obs_run_id, sim_run_id, 
                                              status, obs_run_dir)
    
    # Ensure base directory exists
    mkpath(obs_base_dir)
    
    # Append to jsonl file
    catalog_path = joinpath(obs_base_dir, OBSERVABLES_CATALOG_FILENAME)
    open(catalog_path, "a") do f
        JSON.print(f, entry)
        println(f)  # newline after each entry
    end
    
    println("  ✓ Appended to observables catalog: $obs_run_id")
    
    return entry
end

"""
    _load_observables_catalog(; obs_base_dir="observables") -> Vector{Dict}

Load all observable catalog entries from jsonl file.
Returns empty vector if catalog doesn't exist.
"""
function _load_observables_catalog(; obs_base_dir::String="observables")
    catalog_path = joinpath(obs_base_dir, OBSERVABLES_CATALOG_FILENAME)
    
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
    _observables_catalog_exists(; obs_base_dir="observables") -> Bool

Check if observables catalog file exists.
"""
function _observables_catalog_exists(; obs_base_dir::String="observables")
    return isfile(joinpath(obs_base_dir, OBSERVABLES_CATALOG_FILENAME))
end

"""
    _observables_catalog_count(; obs_base_dir="observables") -> Int

Count entries in observables catalog without loading all into memory.
"""
function _observables_catalog_count(; obs_base_dir::String="observables")
    catalog_path = joinpath(obs_base_dir, OBSERVABLES_CATALOG_FILENAME)
    
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