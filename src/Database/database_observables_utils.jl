# ============================================================================
# OBSERVABLE DATABASE MANAGEMENT SYSTEM
# ============================================================================
#
# This module provides database functionality for managing observable
# calculations on tensor network simulation data.
#
# CONFIG STRUCTURE (Analysis):
# {
#   "simulation": {
#     "system": { ... },
#     "model": { ... },
#     "state": { ... },
#     "algorithm": { ... }
#   },
#   "analysis": {
#     "sweeps": { "selection": "all", ... },
#     "observable": { "type": "...", "params": { ... } }
#   },
#   "description": "..."   ← Ignored for hashing
# }
#
# HASH STRATEGY:
# - Level 1: config["simulation"] → sim_hash → finds simulation data
#   (uses _compute_config_hash from database_utils.jl which normalizes to
#    system/model/state/algorithm only)
# - Level 2: config (normalized to simulation+analysis) → obs_hash → 
#   identifies this observable calculation
#
# DIRECTORY STRUCTURE:
#   observables/
#   ├── observables_index.json
#   └── {algorithm}/
#       └── {sim_run_id}/              ← from simulation hash
#           └── {obs_run_id}/          ← from full config hash
#               ├── observable_config.json
#               ├── metadata.json
#               └── observable_sweep_*.jld2
#
# PATH STRATEGY:
#   - Index stores only: obs_run_id, sim_run_id, algorithm, timestamp (NO obs_run_dir)
#   - Path is COMPUTED on query: obs_base_dir/algorithm/sim_run_id/obs_run_id
#   - This ensures portability (works from any directory)
#
# TYPICAL WORKFLOW:
#   1. Setup: obs_run_id, obs_run_dir = _setup_observable_directory(config, sim_run_id, algorithm)
#   2. Calculate & Save: _save_observable_sweep(obs_value, obs_run_dir, sweep; extra_data=...)
#   3. Finalize: _finalize_observable_run(obs_run_dir, status="completed")
#   4. Later: obs_value = load_observable_sweep(obs_run_dir, sweep)
#
# ============================================================================

using JSON
using SHA
using Dates #: now, format
using JLD2
using Printf

# ============================================================================
# CROSS-PLATFORM JSON I/O HELPERS
# ============================================================================
#
# On Windows, JSON.parsefile() can hold a file lock that is not fully released
# by the time a subsequent open(..., "w") tries to write to the same file.
# This causes "Invalid argument" (EINVAL) errors.
#
# These helpers decouple read and write:
#   _safe_read_json:  reads entire file to string first, then parses
#                     (guarantees the OS file handle is closed before return)
#   _safe_write_json: writes to a .tmp file, then atomically renames
#                     (prevents corruption if the process crashes mid-write)
#
# NOTE: If database_utils.jl is loaded in the same module, these are already
# defined there. The duplicate definitions are kept so each file works
# standalone. Julia will use whichever is loaded first.
#
# ============================================================================

if !(@isdefined _safe_read_json)

"""
    _safe_read_json(path::String) -> Dict

Read and parse a JSON file in a Windows-safe manner.
Reads the entire file to a string first, ensuring the OS file handle
is fully released before returning.
"""
function _safe_read_json(path::String)
    content = read(path, String)
    return JSON.parse(content)
end

"""
    _safe_write_json(path::String, data; indent::Int=2)

Write data to a JSON file in a cross-platform-safe manner.
Writes to a temporary file first, then atomically renames to the target path.
This avoids file lock conflicts on Windows and prevents corruption on all platforms.
"""
function _safe_write_json(path::String, data; indent::Int=2)
    tmp = path * ".tmp"
    open(tmp, "w") do f
        JSON.print(f, data, indent)
    end
    mv(tmp, path, force=true)
end

end # if !(@isdefined _safe_read_json)

# ============================================================================
# PART 1: HASH AND ID GENERATION
# ============================================================================

const ANALYSIS_KEYS = ["simulation", "analysis"]

"""
    _normalize_analysis_config_for_hash(config::Dict) -> Dict

Extract only analysis-relevant sections from config.
Ignores "description" and any other non-essential sections.

This ensures that changing the description doesn't change the hash,
mirroring the behavior of _normalize_config_for_hash in database_utils.jl.
"""
function _normalize_analysis_config_for_hash(config::Dict)
    normalized = Dict{String, Any}()
    for key in ANALYSIS_KEYS
        if haskey(config, key)
            normalized[key] = config[key]
        end
    end
    return normalized
end

"""
    _compute_observable_config_hash(config::Dict) -> String

Compute an 8-character hash that uniquely identifies an observable configuration.

The hash is deterministic: same config always produces the same hash.
This enables finding duplicate calculations.

NOTE: Hashes only "simulation" and "analysis" sections (excludes "description").
- Same simulation + same observable = same hash (detect duplicates)
- Same simulation + different observable = different hash (separate calculations)

# Returns
- String: 8 hex characters (e.g., "f4b2c3d1")
"""
function _compute_observable_config_hash(config::Dict)
    # Normalize: extract only analysis-relevant sections (simulation + analysis)
    # Excludes "description" and other metadata
    normalized = _normalize_analysis_config_for_hash(config)
    
    # Convert to canonical JSON
    config_str = JSON.json(normalized, 2)
    
    # Compute SHA256 and take first 8 characters
    hash_full = bytes2hex(sha256(config_str))
    
    return hash_full[1:8]
end

"""
    _generate_observable_run_id(config::Dict) -> String

Generate a unique identifier for an observable calculation run.

Format: YYYYMMDD_HHMMSS_HHHHHHHH
        └─ timestamp ─┘ └─ hash ─┘

# Returns
- String: Unique observable run ID (e.g., "20241104_153045_f4b2c3d1")
"""
function _generate_observable_run_id(config::Dict)
    # Get current timestamp
    timestamp = Dates.format(now(), "yyyymmdd_HHMMSS")
    
    # Get full config hash (normalized)
    obs_hash = _compute_observable_config_hash(config)
    
    # Combine: timestamp_hash
    return "$(timestamp)_$(obs_hash)"
end

# ============================================================================
# PART 2: SETUP AND INITIALIZATION
# ============================================================================

"""
    _setup_observable_directory(config, sim_run_id, algorithm; obs_base_dir="observables") 
        -> (String, String)

Initialize directory structure and files for a new observable calculation.

Called ONCE at the start of each observable calculation, before processing sweeps.

# What it creates
```
observables/
├── observables_index.json       ← Updated with new calculation
└── {algorithm}/
    └── {sim_run_id}/
        └── {obs_run_id}/
            ├── observable_config.json
            └── metadata.json
```

# Arguments
- `config::Dict`: Full analysis config (with "simulation" and "analysis" sections)
- `sim_run_id::String`: Simulation run identifier (links to data/)
- `algorithm::String`: Algorithm type ("dmrg" or "tdvp")
- `obs_base_dir::String`: Root observable directory (default: "observables")

# Returns
- `obs_run_id::String`: Unique identifier for this observable calculation
- `obs_run_dir::String`: Full path to observable run directory

# Example
```julia
obs_run_id, obs_run_dir = _setup_observable_directory(
    config, 
    "20241103_142530_a3f5b2c1", 
    "tdvp"
)
```
"""
function _setup_observable_directory(config::Dict, sim_run_id::String, algorithm::String; obs_base_dir::String="observables")

    obs_base_dir = abspath(obs_base_dir)

    # Generate unique observable run ID (uses normalized config hash)
    obs_run_id = _generate_observable_run_id(config)
    
    # Create full path: observables/algorithm/sim_run_id/obs_run_id
    obs_run_dir = joinpath(obs_base_dir, algorithm, sim_run_id, obs_run_id)
    
    # Create directory
    mkpath(obs_run_dir)
    
    # ═══════════════════════════════════════════════════════════════════════════
    # Save observable_config.json (full config for reproducibility)
    # ═══════════════════════════════════════════════════════════════════════════
    obs_config_path = joinpath(obs_run_dir, "observable_config.json")
    open(obs_config_path, "w") do f
        JSON.print(f, config, 2)
    end
    
    # ═══════════════════════════════════════════════════════════════════════════
    # Initialize metadata.json
    # ═══════════════════════════════════════════════════════════════════════════
    # Observable info is under config["analysis"]["observable"]
    metadata = Dict(
        "obs_run_id" => obs_run_id,
        "sim_run_id" => sim_run_id,
        "algorithm" => algorithm,
        "observable_type" => config["analysis"]["observable"]["type"],
        "start_time" => string(now()),
        "status" => "running",
        "sweeps_processed" => 0,
        "last_update" => string(now()),
        "sweep_data" => []  # Will fill during calculation
    )
    
    metadata_path = joinpath(obs_run_dir, "metadata.json")
    open(metadata_path, "w") do f
        JSON.print(f, metadata, 2)
    end
    
    # ═══════════════════════════════════════════════════════════════════════════
    # Update master observable index
    # ═══════════════════════════════════════════════════════════════════════════
    _update_observable_index(config, sim_run_id, obs_run_id, algorithm, obs_base_dir)
    
    println("✓ Setup observable directory: $obs_run_dir")
    
    return obs_run_id, obs_run_dir
end

"""
    _update_observable_index(config, sim_run_id, obs_run_id, algorithm, obs_base_dir)

Update the master observable index with a new calculation entry.

The index maps: sim_run_id → [list of observable calculations]

This enables quick lookup of all observables calculated for a simulation.

# Index Structure (v2 - no obs_run_dir stored)
```json
{
  "by_simulation": {
    "20241103_142530_a3f5b2c1": [
      {
        "obs_run_id": "20241104_153045_f4b2c3d1",
        "algorithm": "tdvp",
        "observable_type": "single_site_expectation",
        "observable_params": {...},
        "timestamp": "2024-11-04T15:30:45",
        "obs_config_hash": "f4b2c3d1"
      }
    ]
  }
}
```

# Path Computation
The obs_run_dir is NOT stored. It is computed on query as:
    obs_run_dir = joinpath(obs_base_dir, algorithm, sim_run_id, obs_run_id)
"""
function _update_observable_index(config::Dict, sim_run_id::String,obs_run_id::String, algorithm::String,obs_base_dir::String)

    obs_base_dir = abspath(obs_base_dir)

    index_file = joinpath(obs_base_dir, "observables_index.json")
    
    # Load existing index or create new
    if isfile(index_file)
        index = _safe_read_json(index_file)
    else
        index = Dict(
            "by_simulation" => Dict(),
            "last_updated" => string(now())
        )
    end
    
    # Observable info is under config["analysis"]["observable"]
    # NOTE: No obs_run_dir stored - computed on query
    entry = Dict(
        "obs_run_id" => obs_run_id,
        "algorithm" => algorithm,
        "observable_type" => config["analysis"]["observable"]["type"],
        "observable_params" => config["analysis"]["observable"]["params"],
        "timestamp" => string(now()),
        "obs_config_hash" => _compute_observable_config_hash(config)
    )
    
    # Add to index under sim_run_id
    if !haskey(index["by_simulation"], sim_run_id)
        index["by_simulation"][sim_run_id] = []
    end
    push!(index["by_simulation"][sim_run_id], entry)
    
    # Update timestamp
    index["last_updated"] = string(now())
    
    # Save index
    _safe_write_json(index_file, index)
end

# ============================================================================
# PART 3: SAVING OBSERVABLE DATA
# ============================================================================

"""
    _save_observable_sweep(obs_value, obs_run_dir, sweep; extra_data=Dict())

Save observable value for a single sweep.

Called once per sweep during observable calculation.

# Arguments
- `obs_value`: Observable value (can be scalar, vector, etc.)
- `obs_run_dir::String`: Path to observable run directory
- `sweep::Int`: Sweep number
- `extra_data::Dict`: Optional metadata (from original simulation)

# Side Effects
1. Saves observable_sweep_N.jld2 file
2. Updates metadata.json with sweep info

# Example
```julia
# In calculation loop
for sweep in sweeps_to_process
    obs_value = calculate_observable(...)
    _save_observable_sweep(obs_value, obs_run_dir, sweep; 
                         extra_data=Dict("time" => current_time))
end
```
"""
function _save_observable_sweep(obs_value, obs_run_dir::String, sweep::Int; extra_data::Dict=Dict())

    obs_run_dir = abspath(obs_run_dir)

    # ════════════════════════════════════════════════════════════════════════
    # 1. Save observable to binary file
    # ════════════════════════════════════════════════════════════════════════
    
    filename = @sprintf("observable_sweep_%d.jld2", sweep)
    filepath = joinpath(obs_run_dir, filename)
    
    # Save observable value and extra_data
    jldsave(filepath;
            observable_value=obs_value,
            extra_data=extra_data,
            sweep=sweep)
    
    # ════════════════════════════════════════════════════════════════════════
    # 2. Update metadata.json
    # ════════════════════════════════════════════════════════════════════════
    
    metadata_path = joinpath(obs_run_dir, "metadata.json")
    metadata = _safe_read_json(metadata_path)
    
    # Update progress
    metadata["sweeps_processed"] = sweep
    metadata["last_update"] = string(now())
    
    # Add sweep info
    sweep_info = Dict("sweep" => sweep, "filename" => filename)
    
    # Include extra_data in sweep info if provided
    if !isempty(extra_data)
        sweep_info = merge(sweep_info, extra_data)
    end
    
    push!(metadata["sweep_data"], sweep_info)
    
    # Save updated metadata
    _safe_write_json(metadata_path, metadata)
end

"""
    _finalize_observable_run(obs_run_dir; status="completed")

Mark observable calculation as completed or failed.

# Arguments
- `obs_run_dir::String`: Path to observable run directory
- `status::String`: Final status ("completed" or "failed")
"""
function _finalize_observable_run(obs_run_dir::String; status::String="completed")

    obs_run_dir = abspath(obs_run_dir)

    metadata_path = joinpath(obs_run_dir, "metadata.json")
    metadata = _safe_read_json(metadata_path)
    
    # Update final status
    metadata["status"] = status
    metadata["end_time"] = string(now())
    
    # Save
    _safe_write_json(metadata_path, metadata)
    
    println("  ✓ Observable calculation finalized with status: $status")
end

# ============================================================================
# PART 4: LOADING OBSERVABLE DATA
# ============================================================================

"""
    load_observable_sweep(obs_run_dir, sweep) -> (observable_value, extra_data)

Load observable value for a specific sweep.

# Arguments
- `obs_run_dir::String`: Path to observable run directory
- `sweep::Int`: Sweep number

# Returns
- `(observable_value, extra_data)`: Observable value and metadata
"""
function load_observable_sweep(obs_run_dir::String, sweep::Int)

    obs_run_dir = abspath(obs_run_dir)

    filename = @sprintf("observable_sweep_%d.jld2", sweep)
    filepath = joinpath(obs_run_dir, filename)
    
    if !isfile(filepath)
        error("Observable file not found: $filepath\n" *
              "Sweep $sweep may not have been calculated.")
    end
    
    data = load(filepath)
    
    return data["observable_value"], data["extra_data"]
end

"""
    load_all_observable_results(obs_run_dir) -> Vector

Load all observable results from a calculation run.

# Returns
- Vector of (sweep, observable_value) tuples sorted by sweep number
"""
function load_all_observable_results(obs_run_dir::String)

    obs_run_dir = abspath(obs_run_dir)

    metadata_path = joinpath(obs_run_dir, "metadata.json")
    metadata = _safe_read_json(metadata_path)
    
    results = []
    for sweep_info in metadata["sweep_data"]
        sweep = sweep_info["sweep"]
        obs_value, _ = load_observable_sweep(obs_run_dir, sweep)
        push!(results, (sweep, obs_value))
    end
    
    # Sort by sweep number
    sort!(results, by=x -> x[1])
    
    return results
end

# ============================================================================
# PART 5: QUERY FUNCTIONS
# ============================================================================

"""
    find_observables_for_simulation(sim_run_id; obs_base_dir="observables") -> Vector

Find all observable calculations for a given simulation run.

# Arguments
- `sim_run_id::String`: Simulation run identifier
- `obs_base_dir::String`: Observable base directory

# Returns
- Vector of observable calculation entries (empty if none found)
- Each entry includes computed `obs_run_dir`

# Path Computation
The obs_run_dir is computed fresh using the provided obs_base_dir:
    obs_run_dir = joinpath(obs_base_dir, algorithm, sim_run_id, obs_run_id)

# Example
```julia
obs_calcs = find_observables_for_simulation("20241103_142530_a3f5b2c1")
for obs in obs_calcs
    println("Observable: ", obs["observable_type"])
    println("  Run ID: ", obs["obs_run_id"])
    println("  Directory: ", obs["obs_run_dir"])
end
```
"""
function find_observables_for_simulation(sim_run_id::String; obs_base_dir::String="observables")

    obs_base_dir = abspath(obs_base_dir)

    index_file = joinpath(obs_base_dir, "observables_index.json")
    
    if !isfile(index_file)
        return []  # No observables calculated yet
    end
    
    index = _safe_read_json(index_file)
    
    # Lookup by sim_run_id
    if !haskey(index["by_simulation"], sim_run_id)
        return []  # No observables for this simulation
    end
    
    # Get raw entries
    raw_entries = index["by_simulation"][sim_run_id]
    
    # Compute obs_run_dir for each entry before returning
    results = []
    for entry in raw_entries
        obs_info = copy(entry)  # Don't modify original
        # Compute path: obs_base_dir/algorithm/sim_run_id/obs_run_id
        obs_info["obs_run_dir"] = joinpath(
            obs_base_dir, 
            entry["algorithm"], 
            sim_run_id, 
            entry["obs_run_id"]
        )
        push!(results, obs_info)
    end
    
    return results
end

"""
    observable_already_calculated(config, sim_run_id; obs_base_dir="observables") -> Bool

Check if an observable with this exact config has already been calculated.

Uses normalized config hash to detect duplicates.
"""
function observable_already_calculated(config::Dict, sim_run_id::String; obs_base_dir::String="observables")

    obs_base_dir = abspath(obs_base_dir)

    obs_hash = _compute_observable_config_hash(config)
    observables = find_observables_for_simulation(sim_run_id, obs_base_dir=obs_base_dir)
    
    for obs in observables
        if obs["obs_config_hash"] == obs_hash
            return true
        end
    end
    
    return false
end

"""
    _get_completed_observable_run(config, sim_run_id; obs_base_dir="observables") -> Union{Dict, Nothing}

Check if a COMPLETED observable calculation exists for the given config.

Returns the observable run info dict if found, nothing otherwise.
Only returns runs with status="completed" in metadata.

Mirrors `_get_completed_run()` from simulation database.
"""
function _get_completed_observable_run(config::Dict, sim_run_id::String; obs_base_dir::String="observables")

    obs_base_dir = abspath(obs_base_dir)

    obs_hash = _compute_observable_config_hash(config)
    observables = find_observables_for_simulation(sim_run_id, obs_base_dir=obs_base_dir)
    
    if isempty(observables)
        return nothing
    end
    
    # Check each matching observable's metadata for completion status
    for obs in observables
        if obs["obs_config_hash"] != obs_hash
            continue
        end
        
        obs_run_dir = obs["obs_run_dir"]
        metadata_path = joinpath(obs_run_dir, "metadata.json")
        
        # Skip if metadata doesn't exist
        if !isfile(metadata_path)
            continue
        end
        
        try
            metadata = _safe_read_json(metadata_path)
            if get(metadata, "status", "") == "completed"
                return obs  # Found a completed observable run
            end
        catch e
            @warn "Could not read metadata for observable run $(obs["obs_run_id"]): $e"
            continue
        end
    end
    
    return nothing  # No completed observable run found
end

# ============================================================================
# PART 6: QUERY OBSERVABLES BY CONFIG (Mirrors simulation database pattern)
# ============================================================================

"""
    find_observable_runs_by_config(config::Dict; base_dir="data", obs_base_dir="observables")
        -> Vector{Dict}

Find all observable calculation runs matching this exact config.

Mirrors `find_runs_by_config()` from simulation database.

# Returns
- Vector of observable run info (empty if none found)
- Each entry includes computed `obs_run_dir`

# Example
```julia
config = JSON.parsefile("configs/analysis_magnetization.json")
runs = find_observable_runs_by_config(config)

for run in runs
    println("Run: ", run["obs_run_id"])
    println("Dir: ", run["obs_run_dir"])
end
```
"""
function find_observable_runs_by_config(config::Dict; base_dir::String="data",obs_base_dir::String="observables")

    base_dir = abspath(base_dir)
    obs_base_dir = abspath(obs_base_dir)

    # Simulation config is embedded under "simulation" key
    sim_config = config["simulation"]
    
    sim_runs = _find_runs_by_config(sim_config, base_dir)
    
    if isempty(sim_runs)
        return []  # No simulation data exists
    end
    
    # Get latest simulation run
    sim_run_id = sim_runs[end]["run_id"]
    
    # Find all observables for this simulation (returns computed paths)
    all_obs = find_observables_for_simulation(sim_run_id, obs_base_dir=obs_base_dir)
    
    # Filter by matching normalized config hash
    obs_hash = _compute_observable_config_hash(config)
    matching_runs = filter(obs -> obs["obs_config_hash"] == obs_hash, all_obs)
    
    return matching_runs
end

"""
    get_latest_observable_run_for_config(config::Dict; base_dir="data", obs_base_dir="observables")
        -> Dict or nothing

Get the most recent observable calculation matching this config.

Mirrors `get_latest_run_for_config()` from simulation database.

# Returns
- Dict with observable run info (including computed obs_run_dir), or nothing if not found

# Example
```julia
config = JSON.parsefile("configs/analysis_magnetization.json")
run_info = get_latest_observable_run_for_config(config)

if run_info !== nothing
    obs_run_dir = run_info["obs_run_dir"]
    results = load_all_observable_results(obs_run_dir)
else
    println("Observable not yet calculated")
end
```
"""
function get_latest_observable_run_for_config(config::Dict;base_dir::String="data",obs_base_dir::String="observables")

    base_dir = abspath(base_dir)
    obs_base_dir = abspath(obs_base_dir)

    runs = find_observable_runs_by_config(config, base_dir=base_dir, obs_base_dir=obs_base_dir)
    
    if isempty(runs)
        return nothing
    end
    
    # Sort by timestamp (most recent first)
    sorted_runs = sort(runs, by=r -> r["timestamp"], rev=true)
    
    return sorted_runs[1]
end
