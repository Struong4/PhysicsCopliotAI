# DATA MANAGEMENT SYSTEM - COMPLETE GUIDE

## 📋 Table of Contents
1. [Overview](#overview)
2. [Design Philosophy](#design-philosophy)
3. [Directory Structure](#directory-structure)
4. [Hash-Based Indexing](#hash-based-indexing)
5. [Simulation Data](#simulation-data)
6. [Observable Data](#observable-data)
7. [Saving Data](#saving-data)
8. [Loading Data](#loading-data)
9. [Complete Workflows](#complete-workflows)
10. [Advanced Features](#advanced-features)

---

## Overview

TNCodebase implements a **hash-based data management system** that automatically organizes, indexes, and retrieves simulation and observable data.

### Key Features

✅ **Automatic organization** - No manual file management  
✅ **Hash-based indexing** - O(1) lookup by configuration  
✅ **Duplicate detection** - Prevent redundant calculations  
✅ **Complete provenance** - Track from config to results  
✅ **Two-tier system** - Simulations and observables separate  
✅ **Portable** - Works from any directory  
✅ **Time-based queries** - For TDVP and ED time evolution

### What Gets Saved?

**For each simulation:**
- Complete configuration (config.json)
- Runtime metadata (metadata.json)
- State data (MPS states or ED vectors)
- Results summary

**For each observable calculation:**
- Complete analysis config (observable_config.json)
- Observable metadata (metadata.json)
- Observable values per sweep/state

---

## Design Philosophy

### 1. Config-Driven Everything

**Philosophy:** The configuration completely specifies the calculation.

```julia
# Same config = same hash = same results
config1 = Dict("system" => ..., "model" => ..., "algorithm" => ...)
config2 = Dict("system" => ..., "model" => ..., "algorithm" => ...)

hash1 = _compute_config_hash(config1)
hash2 = _compute_config_hash(config2)

if hash1 == hash2
    # Identical calculations! Reuse existing data.
end
```

**Benefits:**
- Reproducibility guaranteed
- Automatic duplicate detection
- No parameter extraction needed

### 2. Hash-Based Indexing

**Problem:** How to find simulations without scanning all directories?

**Solution:** Hash the config!

```julia
config = Dict("system" => Dict("N" => 20), "model" => ...)
hash = _compute_config_hash(config)  # "a3f5b2c1"

# Now O(1) lookup:
# 1. Compute hash from config
# 2. Look up hash in index
# 3. Get all matching run_ids
```

**Collision probability:**
- 8 hex characters = 32 bits = 4 billion unique values
- 10,000 configs: ~0.001% collision chance
- 100,000 configs: ~0.1% collision chance

### 3. Two-Tier Organization

**Why separate simulations and observables?**

```
Simulation: Expensive (hours)
    ↓
    ├─ Observable 1: Cheap (seconds)
    ├─ Observable 2: Cheap (seconds)
    └─ Observable 3: Cheap (seconds)
```

**Allows:**
- Calculate many observables without re-running simulation
- Share simulation data across analyses
- Independent provenance tracking

### 4. Portable Paths

**Problem:** Absolute paths break when moving data!

**Solution:** Store only identifiers, compute paths on demand.

```julia
# Index stores:
{
  "run_id": "20241103_142530_a3f5b2c1",
  "timestamp": "2024-11-03T14:25:30",
  "algorithm": "dmrg"
  # NO run_dir stored!
}

# Path computed when needed:
function _compute_run_dir(entry, base_dir)
    return joinpath(base_dir, entry["algorithm"], entry["run_id"])
end
```

**Benefits:**
- Move data directory anywhere
- Works from any working directory
- No broken symlinks

---

## Directory Structure

### Simulation Data (data/)

```
data/
├── run_catalog.jsonl              ← Simulation catalog (master index)
├── runs_index.json                ← Legacy hash→run_id mapping
│
├── dmrg/                          ← DMRG simulations
│   └── 20241103_142530_a3f5b2c1/
│       ├── config.json            ← Complete config (reproducibility)
│       ├── metadata.json          ← Runtime info + sweep history
│       ├── sweep_001.jld2         ← MPS after sweep 1
│       ├── sweep_002.jld2         ← MPS after sweep 2
│       └── sweep_050.jld2         ← Final MPS
│
├── tdvp/                          ← TDVP time evolution
│   └── 20241103_151823_b7f2e4d8/
│       ├── config.json
│       ├── metadata.json          ← Includes dt for time queries
│       ├── sweep_001.jld2         ← State at t = 1×dt
│       ├── sweep_002.jld2         ← State at t = 2×dt
│       └── sweep_500.jld2         ← State at t = 500×dt
│
├── ed_spectrum/                   ← ED full spectrum
│   └── 20241103_163045_c8e1f7a9/
│       ├── config.json
│       ├── metadata.json          ← Includes all eigenvalues
│       └── results.jld2           ← Eigenvalues + eigenvectors
│
└── ed_time_evolution/             ← ED time dynamics
    └── 20241103_170512_d9f3a2b4/
        ├── config.json
        ├── metadata.json          ← Includes dt, step history
        ├── state_step_1.jld2      ← State vector at step 1
        ├── state_step_2.jld2      ← State vector at step 2
        └── state_step_200.jld2    ← State vector at step 200
```

### Observable Data (observables/)

```
observables/
├── observables_catalog.jsonl      ← Observable catalog (master index)
├── observables_index.json         ← sim_run_id → obs_run_ids mapping
│
├── dmrg/                          ← Observables on DMRG states
│   └── 20241103_142530_a3f5b2c1/      ← Simulation run_id
│       ├── 20241103_153120_e4a5b3c7/  ← Observable run_id
│       │   ├── observable_config.json ← Analysis config
│       │   ├── metadata.json          ← Observable metadata
│       │   ├── observable_sweep_001.jld2  ← Value at sweep 1
│       │   └── observable_sweep_050.jld2  ← Value at sweep 50
│       └── 20241103_154230_f5b6c4d8/  ← Another observable
│           └── ...
│
├── tdvp/                          ← Observables on TDVP states
│   └── 20241103_151823_b7f2e4d8/
│       └── 20241103_162045_a1b2c3d4/
│           └── ...
│
├── ed_spectrum/                   ← Observables on eigenstates
│   └── 20241103_163045_c8e1f7a9/
│       └── 20241103_170512_b2c3d4e5/
│           ├── observable_config.json
│           ├── metadata.json
│           └── observables.jld2       ← All eigenstate values
│
└── ed_time_evolution/             ← Observables on time-evolved states
    └── 20241103_170512_d9f3a2b4/
        └── 20241103_173045_c3d4e5f6/
            └── ...
```

---

## Hash-Based Indexing

### Run ID Format

```
20241103_142530_a3f5b2c1
└──date──┘ └time┘ └hash─┘
```

**Components:**
1. **Timestamp** (YYYYMMDD_HHMMSS):
   - Ensures uniqueness (two runs at same millisecond unlikely)
   - Enables chronological sorting
   - Human-readable date/time

2. **Config Hash** (8 hex chars):
   - Identifies the configuration
   - Same config → same hash
   - Enables grouping of identical runs

### Hash Computation

```julia
function _compute_config_hash(config::Dict)
    # 1. Normalize: Extract only simulation-relevant keys
    #    (Ignores "info", "description", etc.)
    normalized = _normalize_config_for_hash(config)
    # normalized = Dict with only: system, model, state, algorithm
    
    # 2. Convert to canonical JSON (deterministic formatting)
    config_str = JSON.json(normalized, 2)
    
    # 3. Compute SHA256 hash (256-bit cryptographic hash)
    hash_full = bytes2hex(sha256(config_str))
    # → "a3f5b2c1e4d7f8a9b2c5d8e1f4a7b3c6..."
    
    # 4. Take first 8 characters (32 bits)
    return hash_full[1:8]
    # → "a3f5b2c1"
end
```

**What gets hashed:**
```julia
# ✅ INCLUDED (affects hash):
config["system"]     # System parameters
config["model"]      # Model parameters
config["state"]      # Initial state (if present)
config["algorithm"]  # Algorithm parameters

# ❌ EXCLUDED (doesn't affect hash):
config["info"]        # User notes
config["description"] # Comments
# Any other keys not in SIMULATION_KEYS
```

**Why exclude info/description?**
- Changing a comment shouldn't create a new hash
- Only physics-relevant parameters matter
- Mirrors how scientists think about "same calculation"

### Index Files

**run_catalog.jsonl** (NEW - preferred):
```jsonl
{"run_id":"20241103_142530_a3f5b2c1","config_hash":"a3f5b2c1","algorithm":"dmrg",...}
{"run_id":"20241103_151823_b7f2e4d8","config_hash":"b7f2e4d8","algorithm":"tdvp",...}
```
- One JSON object per line
- Full metadata for each run
- Used by query system

**runs_index.json** (LEGACY):
```json
{
  "a3f5b2c1": {
    "config": {...},
    "runs": [
      {
        "run_id": "20241103_142530_a3f5b2c1",
        "timestamp": "2024-11-03T14:25:30",
        "algorithm": "dmrg"
      }
    ]
  }
}
```
- Hash → list of runs
- Kept for backward compatibility
- Will be deprecated in future

**observables_catalog.jsonl** (NEW):
```jsonl
{"obs_run_id":"20241103_153120_e4a5b3c7","sim_run_id":"20241103_142530_a3f5b2c1",...}
```
- Observable catalog entries
- Links to parent simulation

**observables_index.json**:
```json
{
  "by_simulation": {
    "20241103_142530_a3f5b2c1": [
      {
        "obs_run_id": "20241103_153120_e4a5b3c7",
        "obs_config_hash": "e4a5b3c7",
        "observable_type": "magnetization",
        "algorithm": "dmrg"
      }
    ]
  }
}
```
- sim_run_id → list of observables
- Fast lookup of all observables for a simulation

---

## Simulation Data

### config.json

**Purpose:** Complete specification for reproducibility

**Contents:** Exact copy of input config

```json
{
  "system": {
    "type": "spin",
    "N": 20,
    "S": 0.5
  },
  "model": {
    "name": "heisenberg",
    "params": {
      "Jx": 1.0,
      "Jy": 1.0,
      "Jz": 1.0,
      "hx": 0.0,
      "hy": 0.0,
      "hz": 0.0
    }
  },
  "state": {
    "type": "random",
    "params": {
      "bond_dim": 10
    }
  },
  "algorithm": {
    "type": "dmrg",
    "solver": {
      "type": "lanczos",
      "krylov_dim": 6
    },
    "options": {
      "chi_max": 100,
      "cutoff": 1e-10
    },
    "run": {
      "n_sweeps": 50
    }
  }
}
```

**Use cases:**
- Re-run exact same calculation
- Parameter comparison
- Reproducibility verification

### metadata.json

**Purpose:** Runtime information and sweep history

**DMRG metadata:**
```json
{
  "run_id": "20241103_142530_a3f5b2c1",
  "algorithm": "dmrg",
  "start_time": "2024-11-03T14:25:30.123",
  "status": "completed",
  "last_update": "2024-11-03T14:27:45.678",
  "sweeps_completed": 50,
  "sweep_data": [
    {
      "sweep": 1,
      "energy": -8.512,
      "bond_dim": 45,
      "truncation_error": 1.2e-8,
      "filename": "sweep_001.jld2"
    },
    {
      "sweep": 2,
      "energy": -8.701,
      "bond_dim": 52,
      "truncation_error": 8.4e-9,
      "filename": "sweep_002.jld2"
    }
    // ... all sweeps
  ]
}
```

**TDVP metadata:**
```json
{
  "run_id": "20241103_151823_b7f2e4d8",
  "algorithm": "tdvp",
  "dt": 0.01,                    ← Time step (enables time queries!)
  "start_time": "2024-11-03T15:18:23.456",
  "status": "completed",
  "sweeps_completed": 500,
  "sweep_data": [
    {
      "sweep": 1,
      "time": 0.01,              ← Physical time
      "energy": -8.234,
      "bond_dim": 48,
      "filename": "sweep_001.jld2"
    }
    // ... all time steps
  ]
}
```

**ED Spectrum metadata:**
```json
{
  "run_id": "20241103_163045_c8e1f7a9",
  "algorithm": "ed_spectrum",
  "start_time": "2024-11-03T16:30:45.789",
  "status": "completed",
  "n_states": 1024,              ← Total states computed
  "hilbert_dim": 1024,           ← Hilbert space dimension
  "ground_energy": -8.7245,      ← Ground state energy
  "spectral_gap": 0.4123,        ← Energy gap
  "energies": [                  ← All eigenvalues (quick access!)
    -8.7245,
    -8.3122,
    -8.2401,
    // ... all 1024 eigenvalues
  ]
}
```

**ED Time Evolution metadata:**
```json
{
  "run_id": "20241103_170512_d9f3a2b4",
  "algorithm": "ed_time_evolution",
  "dt": 0.05,                    ← Time step
  "start_time": "2024-11-03T17:05:12.345",
  "status": "completed",
  "steps_completed": 200,
  "step_data": [
    {
      "step": 1,
      "time": 0.05,              ← Physical time
      "filename": "state_step_1.jld2"
    }
    // ... all time steps
  ]
}
```

### State Files

**DMRG/TDVP: sweep_XXX.jld2**

Contents:
```julia
# Load a sweep file
data = load("sweep_025.jld2")

# Available data:
data["mps"]           # MPSTensor object (the state)
data["extra_data"]    # Dictionary with:
  ├─ "energy"         # Energy at this sweep
  ├─ "bond_dim"       # Maximum bond dimension
  ├─ "truncation_error"  # SVD truncation error
  └─ "sweep"          # Sweep number
```

**ED Spectrum: results.jld2**

Contents:
```julia
data = load("results.jld2")

data["energies"]      # Vector{Float64} - all eigenvalues
data["states"]        # Matrix - eigenvectors as columns
data["extra_data"]    # Additional info (optional)
```

**ED Time Evolution: state_step_N.jld2**

Contents:
```julia
data = load("state_step_100.jld2")

data["state"]         # Vector{ComplexF64} - state vector at this time
data["extra_data"]    # Dictionary with:
  ├─ "time"           # Physical time
  └─ "step"           # Step number
```

---

## Observable Data

### observable_config.json

**Purpose:** Complete analysis specification

**Structure:**
```json
{
  "simulation": {
    "system": {...},    ← Embedded simulation config
    "model": {...},
    "state": {...},
    "algorithm": {...}
  },
  "analysis": {
    "observable": {
      "type": "entanglement_entropy",
      "params": {
        "bond": 10
      }
    },
    "sweeps": {
      "selection": "all"    or "last", "range", "specific"
    }
  },
  "description": "Entanglement at bond 10 for all sweeps"
}
```

**Two-level hashing:**
```julia
# Level 1: Find simulation
sim_hash = _compute_config_hash(config["simulation"])
# → Links to simulation data

# Level 2: Identify observable calculation
obs_hash = _compute_observable_config_hash(config)
# → Uses both simulation AND analysis sections
# → Different observables on same simulation = different hash
```

### Observable Files

**observable_sweep_XXX.jld2** (for DMRG/TDVP):
```julia
data = load("observable_sweep_025.jld2")

data["observable_value"]  # The computed value (Float64, Vector, etc.)
data["extra_data"]        # Additional info:
  ├─ "sweep"              # Sweep number
  ├─ "bond"               # Bond index (for entanglement)
  └─ ...                  # Observable-specific data
```

**observables.jld2** (for ED):
```julia
data = load("observables.jld2")

data["observable_values"]  # Vector of values (one per state/step)
data["energies"]           # Energies (if ED spectrum)
  or
data["times"]              # Times (if ED time evolution)
data["extra_data"]         # Parameters and metadata
```

---

## Saving Data

### Simulation Saving Workflow

```julia
# ═══════════════════════════════════════════════════════════════════
# STEP 1: Setup (called ONCE at start)
# ═══════════════════════════════════════════════════════════════════

run_id, run_dir = _setup_run_directory(config, base_dir="data")

# Creates:
#   data/dmrg/20241103_142530_a3f5b2c1/
#   ├── config.json
#   └── metadata.json (initialized)

# ═══════════════════════════════════════════════════════════════════
# STEP 2: Save during simulation (called each sweep)
# ═══════════════════════════════════════════════════════════════════

for sweep in 1:n_sweeps
    # ... run DMRG sweep ...
    
    # Save MPS state
    _save_mps_sweep(
        state,                    # MPSTensor object
        run_dir,
        sweep;
        extra_data=Dict(
            "energy" => energy,
            "bond_dim" => max_bond_dim,
            "truncation_error" => trunc_err
        )
    )
    
    # Creates: sweep_001.jld2, sweep_002.jld2, ...
    # Updates: metadata.json (appends to sweep_data)
end

# ═══════════════════════════════════════════════════════════════════
# STEP 3: Finalize (called ONCE at end)
# ═══════════════════════════════════════════════════════════════════

_finalize_run(run_id, "completed", run_dir)

# Updates:
#   metadata.json: status = "completed"
#   run_catalog.jsonl: appends entry
#   runs_index.json: updates hash mapping
```

### ED Spectrum Saving

```julia
# Setup
run_id, run_dir = _setup_run_directory(config, base_dir="data")

# Run ED
eigenvalues, eigenvectors = solve_spectrum(H, all_states)

# Save results (called ONCE)
_save_ed_spectrum(
    eigenvalues,
    eigenvectors,
    run_dir;
    extra_data=Dict()
)

# Creates: results.jld2
# Updates: metadata.json with summary

# Finalize
_finalize_run(run_id, "completed", run_dir)
```

### ED Time Evolution Saving

```julia
# Setup
run_id, run_dir = _setup_run_directory(config, base_dir="data")

# Prepare evolution
ev_data = prepare_time_evolution(H, psi0)

# Evolve and save (called each step)
for step in 1:n_steps
    t = step * dt
    psi_t = evolve_to_time(ev_data, t)
    
    _save_ed_step(
        psi_t,
        run_dir,
        step;
        extra_data=Dict("time" => t)
    )
    
    # Creates: state_step_1.jld2, state_step_2.jld2, ...
    # Updates: metadata.json (appends to step_data)
end

# Finalize
_finalize_run(run_id, "completed", run_dir)
```

### Observable Saving Workflow

```julia
# ═══════════════════════════════════════════════════════════════════
# STEP 1: Find simulation
# ═══════════════════════════════════════════════════════════════════

sim_config = config["simulation"]
sim_runs = _find_runs_by_config(sim_config, base_dir="data")

if isempty(sim_runs)
    error("Simulation data not found! Run simulation first.")
end

sim_run_id = sim_runs[end]["run_id"]  # Latest run
algorithm = sim_runs[end]["algorithm"]

# ═══════════════════════════════════════════════════════════════════
# STEP 2: Setup observable directory
# ═══════════════════════════════════════════════════════════════════

obs_run_id, obs_run_dir = _setup_observable_directory(
    config,
    sim_run_id,
    algorithm;
    obs_base_dir="observables"
)

# Creates:
#   observables/dmrg/20241103_142530_a3f5b2c1/20241103_153120_e4a5b3c7/
#   ├── observable_config.json
#   └── metadata.json

# ═══════════════════════════════════════════════════════════════════
# STEP 3: Calculate and save (each sweep/state)
# ═══════════════════════════════════════════════════════════════════

for sweep in selected_sweeps
    # Load MPS
    mps, _ = load_mps_sweep(sim_run_dir, sweep)
    
    # Calculate observable
    value = calculate_observable(mps, obs_config)
    
    # Save
    _save_observable_sweep(
        value,
        obs_run_dir,
        sweep;
        extra_data=Dict("bond" => bond)
    )
    
    # Creates: observable_sweep_001.jld2, ...
    # Updates: metadata.json
end

# ═══════════════════════════════════════════════════════════════════
# STEP 4: Finalize
# ═══════════════════════════════════════════════════════════════════

_finalize_observable_run(obs_run_id, "completed", obs_run_dir)

# Updates:
#   metadata.json: status = "completed"
#   observables_catalog.jsonl: appends entry
#   observables_index.json: links to simulation
```

---

## Loading Data

### Load Simulation by Sweep

**DMRG/TDVP:**
```julia
# Method 1: Direct path
mps, extra_data = load_mps_sweep(run_dir, 25)

# Returns:
# mps: MPSTensor object
# extra_data: Dict with energy, bond_dim, etc.

# Method 2: Via query
results = query("sim", algorithm="dmrg", model_name="heisenberg")
run_dir = results[1]["run_dir"]
mps, extra_data = load_mps_sweep(run_dir, 25)
```

**ED:**
```julia
# Spectrum
energies, states, extra_data = load_ed_spectrum(run_dir)

# Time evolution
psi, extra_data = load_ed_step(run_dir, 100)
```

### Load by Time (TDVP/ED Time Evolution)

```julia
# Load state at specific physical time
mps, extra_data, actual_time = load_mps_at_time(run_dir, time=1.5)

# Finds closest saved time:
# - dt = 0.01, t = 1.5 requested
# - Looks for sweep with time ≈ 1.5
# - Returns actual time found

# For ED:
psi, extra_data, actual_time = load_ed_at_time(run_dir, time=1.5)
```

### List Available Times

```julia
# TDVP
times = list_available_times(run_dir)
# → [(1, 0.01), (2, 0.02), ..., (500, 5.00)]
# Format: (sweep, time)

# ED time evolution
times = list_ed_times(run_dir)
# → [(1, 0.05), (2, 0.10), ..., (200, 10.00)]
# Format: (step, time)
```

### Load Observables

```julia
# Single sweep
value, extra_data = load_observable_sweep(obs_run_dir, 25)

# All sweeps
results = load_all_observable_results(obs_run_dir)
# → [(1, value1), (2, value2), ..., (50, value50)]
# Format: (sweep, value)
```

### Query-Based Loading

```julia
# Find simulations by config
config = JSON.parsefile("sim_config.json")
runs = _find_runs_by_config(config, base_dir="data")

# Or use new query system
results = query("sim", algorithm="dmrg", N=20)

# Load latest
if !isempty(results)
    run_dir = results[end]["run_dir"]
    mps, extra = load_mps_sweep(run_dir, 50)
end

# Find observables for simulation
sim_run_id = results[1]["run_id"]
obs_list = find_observables_for_simulation(sim_run_id)

for obs in obs_list
    println("Observable: ", obs["observable_type"])
    obs_dir = obs["obs_run_dir"]
    # Load observable data...
end
```

---

## Complete Workflows

### Workflow 1: Run Simulation and Calculate Observable

```julia
using TNCodebase
using JSON

# ═══════════════════════════════════════════════════════════════════
# PART 1: Run Simulation
# ═══════════════════════════════════════════════════════════════════

sim_config = Dict(
    "system" => Dict("type" => "spin", "N" => 20),
    "model" => Dict("name" => "heisenberg", "params" => Dict(...)),
    "state" => Dict("type" => "random", "params" => Dict("bond_dim" => 10)),
    "algorithm" => Dict("type" => "dmrg", "options" => Dict(...))
)

# Run (auto-saves everything)
state, run_id, run_dir = run_simulation_from_config(sim_config)

println("✓ Simulation completed: $run_id")
println("  Data saved to: $run_dir")

# ═══════════════════════════════════════════════════════════════════
# PART 2: Calculate Observable
# ═══════════════════════════════════════════════════════════════════

obs_config = Dict(
    "simulation" => sim_config,  # Reference simulation
    "analysis" => Dict(
        "observable" => Dict(
            "type" => "entanglement_entropy",
            "params" => Dict("bond" => 10)
        ),
        "sweeps" => Dict("selection" => "all")
    )
)

# Calculate (auto-saves)
obs_run_id, obs_run_dir = run_observable_calculation_from_config(obs_config)

println("✓ Observable calculated: $obs_run_id")
println("  Data saved to: $obs_run_dir")

# ═══════════════════════════════════════════════════════════════════
# PART 3: Load and Analyze
# ═══════════════════════════════════════════════════════════════════

# Load observable results
results = load_all_observable_results(obs_run_dir)

# Plot
using Plots
sweeps = [r[1] for r in results]
entropies = [r[2] for r in results]

plot(sweeps, entropies,
    xlabel="Sweep",
    ylabel="Entanglement Entropy",
    title="S vs Sweep"
)
```

### Workflow 2: Parameter Sweep

```julia
# Sweep over different system sizes
sizes = [10, 20, 30, 40, 50]

for N in sizes
    config = Dict(
        "system" => Dict("type" => "spin", "N" => N),
        "model" => Dict("name" => "heisenberg", ...),
        "state" => Dict(...),
        "algorithm" => Dict("type" => "dmrg", ...)
    )
    
    # Check if already calculated (hash-based!)
    existing = _get_completed_run(config, base_dir="data")
    
    if existing !== nothing
        println("✓ N=$N already calculated (run_id: $(existing["run_id"]))")
        continue
    end
    
    # Run simulation
    println("Running N=$N...")
    state, run_id, run_dir = run_simulation_from_config(config)
    println("  ✓ Completed: $run_id")
end

# Query all results
results = query("sim", algorithm="dmrg", model_name="heisenberg")

# Extract ground energies
energies = []
for result in results
    N = result["core"]["N"]
    E0 = result["results_summary"]["ground_energy"]
    push!(energies, (N, E0))
end

# Plot E0 vs N
using Plots
plot([e[1] for e in energies], [e[2] for e in energies],
    xlabel="System Size N",
    ylabel="Ground Energy",
    marker=:circle
)
```

### Workflow 3: Time-Dependent Observable

```julia
# Run TDVP time evolution
tdvp_config = Dict(
    "system" => Dict("type" => "spin", "N" => 30),
    "model" => Dict("name" => "heisenberg", ...),
    "state" => Dict("type" => "prebuilt", "name" => "polarized", ...),
    "algorithm" => Dict(
        "type" => "tdvp",
        "options" => Dict("dt" => 0.01, ...),
        "run" => Dict("n_sweeps" => 500)
    )
)

state, run_id, run_dir = run_simulation_from_config(tdvp_config)

# Calculate magnetization at all times
obs_config = Dict(
    "simulation" => tdvp_config,
    "analysis" => Dict(
        "observable" => Dict(
            "type" => "magnetization",
            "params" => Dict("operator" => "Z", "site" => 1)
        ),
        "sweeps" => Dict("selection" => "all")
    )
)

obs_run_id, obs_run_dir = run_observable_calculation_from_config(obs_config)

# Load and plot
results = load_all_observable_results(obs_run_dir)

sweeps = [r[1] for r in results]
times = sweeps * 0.01  # dt = 0.01
magnetizations = [r[2] for r in results]

plot(times, magnetizations,
    xlabel="Time t",
    ylabel="⟨σᶻ₁⟩",
    title="Magnetization Decay"
)
```

---

## Advanced Features

### 1. Duplicate Detection

```julia
# Before running simulation
config = JSON.parsefile("sim_config.json")

# Check if already calculated
existing = _get_completed_run(config, base_dir="data")

if existing !== nothing
    println("✓ This simulation already exists!")
    println("  Run ID: ", existing["run_id"])
    println("  Run Dir: ", existing["run_dir"])
    
    # Load existing results
    mps, extra = load_mps_sweep(existing["run_dir"], 50)
else
    println("Running new simulation...")
    run_simulation_from_config(config)
end
```

**How it works:**
1. Compute config hash
2. Search catalog for matching hash
3. Check status == "completed"
4. Return existing run if found

### 2. Force Rerun

```julia
# Even if simulation exists, run again
run_simulation_from_config(config, force_rerun=true)

# Generates new run_id with different timestamp
# Same hash, but new entry in catalog
```

### 3. Path Portability

```julia
# Move data directory anywhere
mv data /new/location/data

# Query still works! Paths computed on demand
results = query("sim", algorithm="dmrg", base_dir="/new/location/data")

# run_dir is computed from:
# base_dir + algorithm + run_id
```

### 4. Cross-Referencing

```julia
# Find all observables for a simulation
sim_results = query("sim", algorithm="ed_spectrum", N=10)
sim_run_id = get_run_ids(sim_results)[1]

# Get observables
obs_list = find_observables_for_simulation(sim_run_id)

println("Simulation: $sim_run_id")
println("Observables:")
for obs in obs_list
    println("  - ", obs["observable_type"])
    println("    Run ID: ", obs["obs_run_id"])
    println("    Directory: ", obs["obs_run_dir"])
end
```

### 5. Metadata Inspection

```julia
# Load metadata without loading large data files
metadata_path = joinpath(run_dir, "metadata.json")
metadata = JSON.parsefile(metadata_path)

# Check convergence
energies = [s["energy"] for s in metadata["sweep_data"]]
plot(energies)

# Check bond dimensions
bond_dims = [s["bond_dim"] for s in metadata["sweep_data"]]
plot(bond_dims)

# For ED spectrum - eigenvalues available in metadata!
if metadata["algorithm"] == "ed_spectrum"
    eigenvalues = metadata["energies"]
    histogram(eigenvalues, xlabel="Energy", ylabel="DOS")
end
```

### 6. Selective Loading

```julia
# Don't need all sweeps? Load only what you need
sweeps_to_load = [1, 10, 20, 30, 40, 50]

data = []
for sweep in sweeps_to_load
    mps, extra = load_mps_sweep(run_dir, sweep)
    push!(data, (sweep, extra["energy"]))
end
```

### 7. Batch Processing

```julia
# Process all DMRG runs for a model
results = query("sim", algorithm="dmrg", model_name="heisenberg")

for result in results
    run_id = result["run_id"]
    run_dir = result["run_dir"]
    N = result["core"]["N"]
    E0 = result["results_summary"]["ground_energy"]
    
    println("Run $run_id: N=$N, E₀=$E0")
    
    # Calculate observable if not already done
    obs_config = create_obs_config(result)
    
    existing_obs = _get_completed_observable_run(
        obs_config, run_id, obs_base_dir="observables"
    )
    
    if existing_obs === nothing
        println("  Calculating observable...")
        run_observable_calculation_from_config(obs_config)
    else
        println("  Observable already calculated")
    end
end
```

---

## Summary

### Key Concepts

✅ **Hash-based indexing** - Fast O(1) lookup by configuration  
✅ **Two-tier organization** - Simulations and observables separate  
✅ **Automatic management** - No manual file organization  
✅ **Portable paths** - Computed on demand, not stored  
✅ **Complete provenance** - From config to results  
✅ **Duplicate detection** - Via config hashing  
✅ **Time-based queries** - For TDVP and ED time evolution

### File Types

| File | Purpose | Format | When Created |
|------|---------|--------|--------------|
| config.json | Reproducibility | JSON | Setup |
| metadata.json | Runtime info | JSON | Setup, updated each sweep |
| sweep_XXX.jld2 | MPS states | Binary | Each DMRG/TDVP sweep |
| results.jld2 | ED spectrum | Binary | After ED diagonalization |
| state_step_N.jld2 | ED states | Binary | Each ED time step |
| observable_sweep_XXX.jld2 | Observable values | Binary | Each observable calculation |
| run_catalog.jsonl | Simulation index | JSONL | After each simulation |
| observables_catalog.jsonl | Observable index | JSONL | After each observable calc |

### Main Functions

**Simulation:**
- `_setup_run_directory()` - Initialize
- `_save_mps_sweep()` - Save state
- `_save_ed_spectrum()` - Save eigenvalues
- `_save_ed_step()` - Save time step
- `_finalize_run()` - Complete
- `load_mps_sweep()` - Load state
- `load_ed_spectrum()` - Load eigenvalues
- `load_ed_step()` - Load time step

**Observable:**
- `_setup_observable_directory()` - Initialize
- `_save_observable_sweep()` - Save value
- `_finalize_observable_run()` - Complete
- `load_observable_sweep()` - Load value
- `load_all_observable_results()` - Load all

**Query:**
- `query()` - Unified query interface
- `_find_runs_by_config()` - Find by config
- `_get_completed_run()` - Get completed run
- `find_observables_for_simulation()` - Find observables

---

**You now understand the complete data management system!** 🎉

**For usage:** See QUERY_SYSTEM_GUIDE.md and CATALOG_QUERY_INTEGRATION.md  
**For catalog details:** See CATALOG_SYSTEM_ARCHITECTURE.md
