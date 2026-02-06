# DATABASE SYSTEM - QUICK REFERENCE

## 🎯 Key Concepts in 30 Seconds

**Hash-Based Indexing:**
```
Config → SHA256 → First 8 chars → "a3f5b2c1"
Same config = Same hash = Find existing data!
```

**Run ID Format:**
```
20241103_142530_a3f5b2c1
└──date──┘ └time┘ └hash─┘
```

**Two-Tier System:**
```
data/           → Simulations (expensive)
observables/    → Observables (cheap, many per simulation)
```

---

## 📁 Directory Structure

```
data/
├── run_catalog.jsonl          # Master index (JSONL)
├── runs_index.json            # Legacy hash lookup
└── {algorithm}/               # dmrg, tdvp, ed_spectrum, ed_time_evolution
    └── {run_id}/
        ├── config.json        # Complete config
        ├── metadata.json      # Runtime info + sweep history
        └── [data files]       # sweep_*.jld2 or results.jld2

observables/
├── observables_catalog.jsonl  # Master index
├── observables_index.json     # sim_run_id → obs lookup
└── {algorithm}/
    └── {sim_run_id}/          # Parent simulation
        └── {obs_run_id}/      # Observable calculation
            ├── observable_config.json
            ├── metadata.json
            └── observable_*.jld2
```

---

## 💾 What Files Contain

| File | Algorithm | Contents |
|------|-----------|----------|
| **config.json** | All | Complete simulation/observable config |
| **metadata.json** | All | Runtime info, status, sweep/step history |
| **sweep_NNN.jld2** | DMRG/TDVP | MPS state at sweep N |
| **results.jld2** | ED Spectrum | All eigenvalues + eigenvectors |
| **state_step_N.jld2** | ED Time Evol | State vector at step N |
| **observable_sweep_N.jld2** | Observables | Observable value at sweep N |

---

## 🔧 Essential Functions

### Saving (Auto-Called by Runners)

```julia
# Simulation setup
run_id, run_dir = _setup_run_directory(config, base_dir="data")

# Save during simulation
_save_mps_sweep(state, run_dir, sweep; extra_data=...)     # DMRG/TDVP
_save_ed_spectrum(energies, states, run_dir; extra_data...)  # ED Spectrum
_save_ed_step(psi, run_dir, step; extra_data...)           # ED Time

# Finalize
_finalize_run(run_id, "completed", run_dir)
```

### Loading (User-Called)

```julia
# Load simulation state
mps, extra = load_mps_sweep(run_dir, 25)           # DMRG/TDVP at sweep 25
energies, states, extra = load_ed_spectrum(run_dir)  # All ED eigenstates
psi, extra = load_ed_step(run_dir, 100)            # ED at step 100

# Load by time (TDVP/ED time evolution)
mps, extra, t = load_mps_at_time(run_dir, time=1.5)
psi, extra, t = load_ed_at_time(run_dir, time=1.5)

# Load observables
value, extra = load_observable_sweep(obs_run_dir, 25)
results = load_all_observable_results(obs_run_dir)  # [(sweep, value), ...]
```

### Querying (Best Way!)

```julia
# New unified query system (RECOMMENDED)
results = query("sim", algorithm="dmrg", N=20, model_name="heisenberg")
obs_results = query("obs", observable_type="entanglement_entropy")

# Legacy functions (still work)
runs = _find_runs_by_config(config, base_dir="data")
existing = _get_completed_run(config, base_dir="data")
obs_list = find_observables_for_simulation(sim_run_id, obs_base_dir="observables")
```

---

## 🚀 Common Workflows

### 1. Run and Save (Automatic)

```julia
# Just run - everything auto-saved!
state, run_id, run_dir = run_simulation_from_config(config)
# ✓ config.json saved
# ✓ metadata.json created & updated
# ✓ sweep_*.jld2 files saved
# ✓ Catalog entry added
```

### 2. Check for Existing Data

```julia
# Before running
existing = _get_completed_run(config, base_dir="data")

if existing !== nothing
    println("Already calculated: ", existing["run_id"])
    run_dir = existing["run_dir"]
    # Load existing data...
else
    # Run new simulation
    run_simulation_from_config(config)
end
```

### 3. Query and Load

```julia
# Find simulations
results = query("sim", algorithm="dmrg", model_name="heisenberg")

# Load latest
run_dir = results[end]["run_dir"]
mps, extra = load_mps_sweep(run_dir, 50)
```

### 4. Calculate Observable on Existing Simulation

```julia
# Reference existing simulation
obs_config = Dict(
    "simulation" => sim_config,  # Existing simulation config
    "analysis" => Dict(
        "observable" => Dict("type" => "entanglement_entropy", ...),
        "sweeps" => Dict("selection" => "all")
    )
)

# Calculate (auto-saved)
obs_run_id, obs_run_dir = run_observable_calculation_from_config(obs_config)

# Load results
results = load_all_observable_results(obs_run_dir)
```

---

## 🎨 metadata.json Examples

### DMRG

```json
{
  "run_id": "20241103_142530_a3f5b2c1",
  "algorithm": "dmrg",
  "status": "completed",
  "sweeps_completed": 50,
  "sweep_data": [
    {"sweep": 1, "energy": -8.512, "bond_dim": 45, "filename": "sweep_001.jld2"},
    {"sweep": 2, "energy": -8.701, "bond_dim": 52, "filename": "sweep_002.jld2"}
  ]
}
```

### TDVP

```json
{
  "run_id": "20241103_151823_b7f2e4d8",
  "algorithm": "tdvp",
  "dt": 0.01,  ← Enables time queries!
  "sweeps_completed": 500,
  "sweep_data": [
    {"sweep": 1, "time": 0.01, "energy": -8.234, "filename": "sweep_001.jld2"}
  ]
}
```

### ED Spectrum

```json
{
  "run_id": "20241103_163045_c8e1f7a9",
  "algorithm": "ed_spectrum",
  "n_states": 1024,
  "ground_energy": -8.7245,
  "spectral_gap": 0.4123,
  "energies": [-8.7245, -8.3122, ...]  ← Quick access without loading JLD2!
}
```

### ED Time Evolution

```json
{
  "run_id": "20241103_170512_d9f3a2b4",
  "algorithm": "ed_time_evolution",
  "dt": 0.05,  ← Enables time queries!
  "steps_completed": 200,
  "step_data": [
    {"step": 1, "time": 0.05, "filename": "state_step_1.jld2"}
  ]
}
```

---

## 🔍 Hash System Deep Dive

### What Gets Hashed (Simulations)

```julia
✅ INCLUDED:
config["system"]      # System parameters
config["model"]       # Model parameters
config["state"]       # Initial state (if present)
config["algorithm"]   # Algorithm parameters

❌ EXCLUDED:
config["info"]        # User notes (doesn't affect physics!)
config["description"] # Comments
```

### What Gets Hashed (Observables)

```julia
✅ INCLUDED:
config["simulation"]  # Embedded simulation config
config["analysis"]    # Observable type + parameters

❌ EXCLUDED:
config["description"] # Comments
```

### Collision Probability

```
Hash length: 8 hex chars = 32 bits = 4,294,967,296 unique values

Configs    Collision Chance
  1,000    0.00001%
 10,000    0.001%
100,000    0.1%
```

**Birthday paradox applies:** 50% collision at ~65,000 configs.  
**In practice:** Very unlikely for typical usage!

---

## 📊 File Size Estimates

### Simulation Data

```
DMRG/TDVP (N=50, χ=100, 50 sweeps):
  config.json:      ~2 KB
  metadata.json:    ~10 KB (grows with sweeps)
  sweep_*.jld2:     ~1 MB each × 50 = 50 MB
  Total per run:    ~50 MB

ED Spectrum (N=10, all 1024 states):
  config.json:      ~2 KB
  metadata.json:    ~100 KB (all eigenvalues!)
  results.jld2:     ~16 MB (1024×1024 complex matrix)
  Total per run:    ~16 MB

ED Time Evolution (N=10, 200 steps):
  config.json:      ~2 KB
  metadata.json:    ~20 KB
  state_step_*.jld2: ~16 KB each × 200 = 3.2 MB
  Total per run:    ~3.2 MB
```

### Observable Data

```
Observable per sweep (typical):
  observable_sweep_*.jld2: ~1-10 KB each
  
50 sweeps × 10 KB = 500 KB per observable calculation

Multiple observables on same simulation:
  3 observables × 500 KB = 1.5 MB total
```

---

## 🎯 Pro Tips

### Tip 1: Use Query System

```julia
# ❌ Don't manually parse directories
for dir in readdir("data/dmrg")
    config = JSON.parsefile(joinpath("data/dmrg", dir, "config.json"))
    # ... manual filtering ...
end

# ✅ Use query system
results = query("sim", algorithm="dmrg", N=20)
```

### Tip 2: Check Before Running

```julia
# Always check for existing data
existing = _get_completed_run(config, base_dir="data")

if existing === nothing
    run_simulation_from_config(config)
else
    println("Using existing run: ", existing["run_id"])
end
```

### Tip 3: Metadata for Quick Checks

```julia
# Don't load JLD2 if you just need energy
metadata = JSON.parsefile(joinpath(run_dir, "metadata.json"))
energy = metadata["sweep_data"][end]["energy"]  # Last sweep energy

# For ED spectrum - eigenvalues in metadata!
if metadata["algorithm"] == "ed_spectrum"
    gap = metadata["spectral_gap"]  # No JLD2 loading needed!
end
```

### Tip 4: Selective Loading

```julia
# Don't load all 50 sweeps if you only need 5
important_sweeps = [1, 10, 20, 30, 50]

for sweep in important_sweeps
    mps, extra = load_mps_sweep(run_dir, sweep)
    # Process...
end
```

### Tip 5: Force Rerun When Needed

```julia
# Force new run even if config exists
run_simulation_from_config(config, force_rerun=true)

# Useful for:
# - Testing algorithm changes
# - Generating ensemble
# - Verifying reproducibility
```

---

## 🔗 Quick Links

**Full Guides:**
- DATA_MANAGEMENT_GUIDE.md - This system in detail
- QUERY_SYSTEM_GUIDE.md - Query API reference
- CATALOG_SYSTEM_ARCHITECTURE.md - How catalogs work

**Related:**
- CATALOG_QUERY_INTEGRATION.md - Complete workflows
- ED_USER_GUIDE.md - ED-specific data handling

---

**This cheat sheet is your quick reference - keep it handy!** 📋
