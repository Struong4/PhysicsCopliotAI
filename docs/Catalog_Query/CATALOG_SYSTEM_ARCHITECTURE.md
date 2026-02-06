# CATALOG SYSTEM ARCHITECTURE

## 📋 Table of Contents
1. [Overview](#overview)
2. [Architecture Design](#architecture-design)
3. [File Structure](#file-structure)
4. [Catalog Schemas](#catalog-schemas)
5. [Indexing System](#indexing-system)
6. [Catalog Creation Flow](#catalog-creation-flow)
7. [Hash-Based Deduplication](#hash-based-deduplication)
8. [Implementation Details](#implementation-details)

---

## Overview

The **Catalog System** is TNCodebase's metadata indexing and organization layer that enables fast, flexible queries over simulations and observables without loading actual data files.

### Purpose

**Without catalogs:**
```julia
# Would need to scan all directories
for dir in readdir("data/dmrg")
    config = JSON.parsefile(joinpath(dir, "config.json"))
    if config["model"]["name"] == "heisenberg"
        # Found one!
    end
end
# Slow! Must read every config.json
```

**With catalogs:**
```julia
# Instant query over pre-indexed metadata
results = query("sim", model_name="heisenberg")
# Fast! Reads only run_catalog.jsonl
```

### Key Features

✅ **Fast queries** - O(N) scan of lightweight JSONL, not O(N) file opens  
✅ **Flexible filtering** - Query by any combination of parameters  
✅ **Automatic indexing** - Catalogs updated after each run  
✅ **Deduplication** - Prevents duplicate runs via config hashing  
✅ **Two-tier system** - Simulations and observables cataloged separately  
✅ **Reproducibility** - Config hash ensures exact reproducibility

---

## Architecture Design

### Two Separate Catalog Systems

```
TNCodebase/
├── data/                           ← Simulation data
│   ├── run_catalog.jsonl          ← Simulation catalog
│   ├── runs_index.json            ← Quick lookup index
│   └── [algorithm]/[run_id]/      ← Actual simulation data
│
└── observables/                    ← Observable data
    ├── observables_catalog.jsonl  ← Observable catalog
    └── [algorithm]/[sim_run_id]/[obs_run_id]/  ← Observable data
```

### Why Separate?

| Simulation Catalog | Observable Catalog |
|-------------------|-------------------|
| **What:** Metadata about simulations | **What:** Metadata about observable calculations |
| **Where:** `data/run_catalog.jsonl` | **Where:** `observables/observables_catalog.jsonl` |
| **Schema:** System, model, algorithm, state | **Schema:** Observable type, simulation reference, analysis params |
| **Updated:** After simulation completes | **Updated:** After observable calculation completes |
| **Queries:** Find simulations by parameters | **Queries:** Find observables by type/simulation |

### Design Principles

1. **Append-only JSONL** - Never modify existing entries, always append
2. **One line per run** - Each catalog entry is a single JSON line
3. **Self-contained** - Catalog has all info needed for querying
4. **Reference by ID** - Observables reference simulations by run_id
5. **Config hash** - Exact deduplication via SHA256 hash

---

## File Structure

### Simulation Catalog Files

```
data/
├── run_catalog.jsonl               # Main catalog (JSONL format)
├── runs_index.json                 # Quick lookup index
└── [algorithm]/                    # Organized by algorithm
    └── [run_id]/                   # One directory per run
        ├── config.json             # Exact configuration used
        ├── metadata.json           # Run metadata (status, time, etc.)
        ├── results.jld2 (or sweep_*.jld2)  # Actual data
        └── ...
```

**Catalog entry example (one line in run_catalog.jsonl):**
```json
{"run_id":"20260206_120534_a3f8b912","config_hash":"d4f2a1b8...","timestamp":"2026-02-06T12:05:34","status":"completed","core":{"algorithm":"dmrg","system_type":"spin","N":20,"S":0.5,"dtype":"ComplexF64"},"algorithm_params":{"chi_max":100,"n_sweeps":50,"cutoff":1e-8},"model":{"kind":"prebuilt","name":"heisenberg","params":{"Jx":1.0,"Jy":1.0,"Jz":1.0}},"state":{"kind":"prebuilt","name":"neel"},"results_summary":{"ground_energy":-8.724,"final_bond_dim":45,"sweeps_completed":50}}
```

### Observable Catalog Files

```
observables/
├── observables_catalog.jsonl       # Main catalog (JSONL format)
└── [sim_algorithm]/                # Organized by simulation algorithm
    └── [sim_run_id]/               # One directory per simulation
        └── [obs_run_id]/           # One directory per observable calc
            ├── config.json         # Observable config (includes sim ref)
            ├── metadata.json       # Observable metadata
            └── observables.jld2    # Observable data
```

**Catalog entry example:**
```json
{"obs_run_id":"20260206_130215_ed319ded","sim_run_id":"20260206_120534_a3f8b912","config_hash":"a7e3c2d9...","timestamp":"2026-02-06T13:02:15","status":"completed","simulation":{"core":{"algorithm":"dmrg","N":20},"model":{"name":"heisenberg"},"state":{"kind":"prebuilt","name":"neel"}},"observable":{"type":"entanglement_entropy","params":{"bond":10}},"analysis_params":{"sweep_selection":{"type":"last"}}}
```

---

## Catalog Schemas

### Simulation Catalog Entry Schema

```json
{
  "run_id": "20260206_120534_a3f8b912",        // Unique run identifier
  "config_hash": "d4f2a1b8c3e9f7a2...",        // SHA256 of config (deduplication)
  "timestamp": "2026-02-06T12:05:34",          // When run was created
  "status": "completed",                        // completed, failed, running
  
  "core": {                                     // Core system properties
    "algorithm": "dmrg",                        // Algorithm type
    "system_type": "spin",                      // System type
    "N": 20,                                    // System size (or N_spins, nmax)
    "S": 0.5,                                   // Spin value (if spin system)
    "dtype": "ComplexF64"                       // Data type
  },
  
  "algorithm_params": {                         // Algorithm-specific parameters
    "chi_max": 100,                             // Max bond dimension (DMRG/TDVP)
    "n_sweeps": 50,                             // Number of sweeps (DMRG)
    "dt": 0.01,                                 // Time step (TDVP/ED time evolution)
    "cutoff": 1e-8                              // Truncation cutoff
    // ... varies by algorithm
  },
  
  "model": {                                    // Model information
    "kind": "prebuilt",                         // "prebuilt" or "custom"
    "name": "heisenberg",                       // Model name (if prebuilt)
    "params": {                                 // Model parameters
      "Jx": 1.0,
      "Jy": 1.0,
      "Jz": 1.0
    }
  },
  
  "state": {                                    // Initial state (if applicable)
    "kind": "prebuilt",                         // "prebuilt", "random", "custom"
    "name": "neel",                             // State name (if prebuilt)
    "params": {                                 // State parameters
      "bond_dim": 10                            // (if random MPS)
    }
  },
  
  "results_summary": {                          // Key results (optional)
    "ground_energy": -8.724,                    // Ground state energy
    "final_bond_dim": 45,                       // Final bond dimension
    "sweeps_completed": 50                      // Convergence info
  }
}
```

**Note:** `state` field is **optional** - not present for `ed_spectrum` which computes eigenstates directly.

### Observable Catalog Entry Schema

```json
{
  "obs_run_id": "20260206_130215_ed319ded",    // Unique observable run ID
  "sim_run_id": "20260206_120534_a3f8b912",    // Reference to simulation run
  "config_hash": "a7e3c2d9...",                 // Hash of observable config
  "timestamp": "2026-02-06T13:02:15",          // When calculation was done
  "status": "completed",                        // completed, failed
  
  "simulation": {                               // Embedded simulation info
    "core": {                                   // Copy of simulation core
      "algorithm": "dmrg",
      "system_type": "spin",
      "N": 20,
      "S": 0.5,
      "dtype": "ComplexF64"
    },
    "algorithm_params": {                       // Copy of simulation algo params
      "chi_max": 100,
      "n_sweeps": 50
    },
    "model": {                                  // Copy of simulation model
      "kind": "prebuilt",
      "name": "heisenberg",
      "params": {"Jx": 1.0, "Jy": 1.0, "Jz": 1.0}
    },
    "state": {                                  // Copy of simulation state (if exists)
      "kind": "prebuilt",
      "name": "neel"
    }
  },
  
  "observable": {                               // Observable being calculated
    "type": "entanglement_entropy",             // Observable type
    "params": {                                 // Observable-specific params
      "bond": 10                                // Bond to cut (for entanglement)
    }
  },
  
  "analysis_params": {                          // Which states/sweeps analyzed
    "sweep_selection": {                        // For DMRG/TDVP
      "type": "last"                            // "last", "all", "range", "specific"
    },
    "state_selection": {                        // For ED
      "type": "all"                             // "all", "range", "specific"
    },
    "step_selection": {                         // For time evolution
      "type": "all"                             // "all", "range", "specific"
    }
  }
}
```

---

## Indexing System

### Primary Index: JSONL Catalogs

**Format:** JSONL (JSON Lines) - one JSON object per line

**Why JSONL?**
- ✅ Append-only (safe for concurrent writes)
- ✅ Human-readable
- ✅ Easy to parse line-by-line
- ✅ Each entry is self-contained
- ✅ No need to load entire file to append

**Example `run_catalog.jsonl`:**
```jsonl
{"run_id":"20260201_143022_a4f3b891","config_hash":"abc123...","status":"completed",...}
{"run_id":"20260201_151533_b7e9c123","config_hash":"def456...","status":"completed",...}
{"run_id":"20260201_154411_c8d4e567","config_hash":"ghi789...","status":"completed",...}
```

### Secondary Index: runs_index.json

**Purpose:** Fast lookup of run directories by run_id

**Format:** JSON dictionary mapping run_id → path

**Example `runs_index.json`:**
```json
{
  "20260201_143022_a4f3b891": "data/dmrg/20260201_143022_a4f3b891",
  "20260201_151533_b7e9c123": "data/dmrg/20260201_151533_b7e9c123",
  "20260201_154411_c8d4e567": "data/dmrg/20260201_154411_c8d4e567"
}
```

**Usage:**
```julia
# Load index
index = JSON.parsefile("data/runs_index.json")

# Fast lookup
run_dir = index["20260201_143022_a4f3b891"]
# → "data/dmrg/20260201_143022_a4f3b891"
```

---

## Catalog Creation Flow

### Simulation Catalog Update Flow

```
1. Simulation completes
   ↓
2. _finalize_run(run_id, status, run_dir)
   ↓
3. _append_to_catalog(config, run_id, status, run_dir)
   ↓
4. Extract catalog entry from config
   - _extract_core(config)
   - _extract_algorithm_params(config)
   - _extract_model(config)
   - _extract_state(config)        ← Optional!
   - _extract_results_summary(config, run_dir)
   ↓
5. Compute config_hash
   - SHA256 of normalized config JSON
   ↓
6. Append entry to run_catalog.jsonl
   - One line, JSON object
   ↓
7. Update runs_index.json
   - Add run_id → run_dir mapping
   ↓
8. Done! Catalog updated
```

### Observable Catalog Update Flow

```
1. Observable calculation completes
   ↓
2. _finalize_observable_run(obs_run_id, status, obs_run_dir)
   ↓
3. _append_to_observables_catalog(config, obs_run_id, sim_run_id, status, obs_run_dir)
   ↓
4. Extract catalog entry
   - _extract_simulation_info_for_observable(config)
     - Extracts simulation core, model, state, algo params
   - _extract_observable_info(config)
     - Observable type and parameters
   - _extract_analysis_params(config)
     - Which states/sweeps/steps were analyzed
   ↓
5. Compute config_hash
   - SHA256 of observable config
   ↓
6. Append entry to observables_catalog.jsonl
   - One line, JSON object
   ↓
7. Done! Observable catalog updated
```

---

## Hash-Based Deduplication

### Config Hashing

**Purpose:** Prevent running identical simulations twice

**Algorithm:**
1. Load config dictionary
2. Normalize (sort keys, consistent formatting)
3. Convert to canonical JSON string
4. Compute SHA256 hash
5. Hash = first 16 characters (64 bits)

**Implementation:**
```julia
function _compute_config_hash(config::Dict)
    # Normalize by sorting keys recursively
    normalized = _normalize_dict(config)
    
    # Convert to JSON string (deterministic)
    json_str = JSON.json(normalized, 2)
    
    # Hash
    full_hash = bytes2hex(sha256(json_str))
    
    # Return first 16 characters
    return full_hash[1:16]
end
```

### Deduplication Check

**Before running simulation:**
```julia
function _check_existing_run(config::Dict; base_dir::String)
    # Compute hash
    config_hash = _compute_config_hash(config)
    
    # Load catalog
    catalog_file = joinpath(base_dir, "run_catalog.jsonl")
    
    # Search for matching hash
    for line in eachline(catalog_file)
        entry = JSON.parse(line)
        if entry["config_hash"] == config_hash && entry["status"] == "completed"
            # Found exact match!
            return entry["run_id"]
        end
    end
    
    # No match found
    return nothing
end
```

**Behavior:**
- If `force_rerun=false` (default): Skip if hash found with status="completed"
- If `force_rerun=true`: Run anyway, new run_id generated

---

## Implementation Details

### Key Files

```
src/Database/
├── database_catalog.jl              # Simulation catalog system
│   ├── _extract_core()
│   ├── _extract_algorithm_params()
│   ├── _extract_model()
│   ├── _extract_state()           ← Optional extraction
│   ├── _extract_results_summary()
│   ├── _extract_catalog_entry()
│   ├── _append_to_catalog()
│   └── _load_catalog()
│
├── database_observables_catalog.jl  # Observable catalog system
│   ├── _extract_simulation_info_for_observable()
│   ├── _extract_observable_info()
│   ├── _extract_analysis_params()
│   ├── _extract_observable_catalog_entry()
│   ├── _append_to_observables_catalog()
│   └── _load_observables_catalog()
│
└── database_utils.jl                # Shared utilities
    ├── _setup_run_directory()
    ├── _compute_config_hash()
    └── _check_existing_run()
```

### Catalog File Operations

**Reading (Loading):**
```julia
function _load_catalog(; base_dir::String="data")
    catalog_file = joinpath(base_dir, "run_catalog.jsonl")
    
    if !isfile(catalog_file)
        return Dict{String, Any}[]  # Empty catalog
    end
    
    entries = Dict{String, Any}[]
    for line in eachline(catalog_file)
        push!(entries, JSON.parse(line))
    end
    
    return entries
end
```

**Writing (Appending):**
```julia
function _append_to_catalog(config::Dict, run_id::String, 
                           status::String, run_dir::String;
                           base_dir::String="data")
    # Extract catalog entry
    entry = _extract_catalog_entry(config, run_id, status, run_dir)
    
    # Append to catalog file
    catalog_file = joinpath(base_dir, "run_catalog.jsonl")
    open(catalog_file, "a") do f
        JSON.print(f, entry)
        println(f)  # Newline for next entry
    end
    
    # Update runs index
    _update_runs_index(run_id, run_dir, base_dir)
end
```

### State Extraction (Conditional)

**Critical feature:** ED spectrum has no initial state!

```julia
function _extract_catalog_entry(config::Dict, run_id::String, 
                               status::String, run_dir::String)
    entry = Dict{String, Any}(
        "run_id" => run_id,
        "config_hash" => _compute_config_hash(config),
        "timestamp" => Dates.format(now(), "yyyy-mm-ddTHH:MM:SS"),
        "status" => status,
        "core" => _extract_core(config),
        "algorithm_params" => _extract_algorithm_params(config),
        "model" => _extract_model(config),
        "results_summary" => _extract_results_summary(config, run_dir)
    )
    
    # Only extract state if present (ed_spectrum doesn't have initial state)
    if haskey(config, "state")
        entry["state"] = _extract_state(config)
    end
    
    return entry
end
```

**Why conditional?**
- DMRG/TDVP/ED time evolution: Have initial state
- ED spectrum: Computes eigenstates directly, no initial state

---

## Catalog Integrity

### Validation

**On catalog load:**
```julia
function _validate_catalog_entry(entry::Dict)
    # Required fields
    required = ["run_id", "config_hash", "timestamp", "status", "core", "model"]
    
    for field in required
        if !haskey(entry, field)
            @warn "Catalog entry missing field: $field" entry
            return false
        end
    end
    
    return true
end
```

### Corruption Recovery

**If catalog is corrupted:**
```julia
# Rebuild from run directories
function rebuild_catalog(; base_dir::String="data")
    entries = Dict{String, Any}[]
    
    # Scan all algorithm directories
    for algo in readdir(base_dir)
        algo_dir = joinpath(base_dir, algo)
        !isdir(algo_dir) && continue
        
        for run_id in readdir(algo_dir)
            run_dir = joinpath(algo_dir, run_id)
            !isdir(run_dir) && continue
            
            # Load config
            config_file = joinpath(run_dir, "config.json")
            !isfile(config_file) && continue
            
            config = JSON.parsefile(config_file)
            
            # Load metadata
            metadata_file = joinpath(run_dir, "metadata.json")
            metadata = JSON.parsefile(metadata_file)
            
            # Recreate entry
            entry = _extract_catalog_entry(
                config, run_id, metadata["status"], run_dir
            )
            
            push!(entries, entry)
        end
    end
    
    # Write new catalog
    catalog_file = joinpath(base_dir, "run_catalog.jsonl")
    open(catalog_file, "w") do f
        for entry in entries
            JSON.print(f, entry)
            println(f)
        end
    end
    
    println("✓ Rebuilt catalog with $(length(entries)) entries")
end
```

---

## Performance Characteristics

### Catalog Size

**Simulation catalog:**
- ~1-2 KB per entry (depending on model complexity)
- 1000 runs ≈ 1-2 MB catalog file
- Still fast to load and query

**Observable catalog:**
- ~2-3 KB per entry (includes simulation info)
- 1000 observables ≈ 2-3 MB catalog file

### Query Performance

**Loading catalog:**
```
N=100:   ~10 ms
N=1000:  ~50 ms
N=10000: ~500 ms
```

**Filtering after load:**
```
Linear scan: O(N)
Typical: 1-10 ms for N=1000
```

**Comparison to directory scanning:**
```
Catalog query:    10 ms (load) + 5 ms (filter) = 15 ms
Directory scan:   1000 × 20 ms (open config.json) = 20,000 ms

Speedup: 1300x faster!
```

---

## Design Rationale

### Why JSONL instead of SQLite?

| JSONL | SQLite |
|-------|--------|
| ✅ Simple, no dependencies | Requires SQL library |
| ✅ Human-readable | Binary format |
| ✅ Append-only (safe) | Requires transactions |
| ✅ Easy to version control | Hard to diff |
| ✅ No schema migrations | Schema migrations needed |
| ⚠️ Linear scan queries | Fast indexed queries |

**Decision:** JSONL wins for simplicity and human readability. Performance is acceptable for expected catalog sizes (< 10,000 entries).

### Why Two Separate Catalogs?

**Could have one unified catalog:**
```json
{"type": "simulation", "run_id": "...", ...}
{"type": "observable", "obs_run_id": "...", ...}
```

**Why separate:**
1. **Clear separation of concerns** - Simulations vs analyses
2. **Different base directories** - data/ vs observables/
3. **Different schemas** - Avoid complex union types
4. **Easier querying** - Don't mix unrelated data
5. **Future extensibility** - Can add more catalog types

### Why Config Hashing?

**Alternative:** Check all config fields manually

**Problems:**
- Floating point comparison issues
- Nested dict comparison complexity
- Easy to miss fields

**Hashing wins:**
- ✅ Exact reproducibility
- ✅ Simple implementation
- ✅ Works for any config structure
- ✅ Collision probability negligible (SHA256)

---

## Summary

The catalog system provides:

✅ **Fast indexing** - JSONL format, O(N) queries  
✅ **Automatic updates** - Catalogs built during simulation  
✅ **Deduplication** - SHA256 config hashing  
✅ **Two-tier system** - Simulations and observables  
✅ **Conditional fields** - Handles algorithms without states  
✅ **Reproducibility** - Exact config hashing  
✅ **Human-readable** - JSONL format  
✅ **Corruption recovery** - Can rebuild from run directories

**Next:** See QUERY_SYSTEM_GUIDE.md for how to query these catalogs!
