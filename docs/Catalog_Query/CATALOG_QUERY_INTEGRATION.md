# CATALOG-QUERY INTEGRATION GUIDE

## 📋 Table of Contents
1. [Overview](#overview)
2. [Complete Data Flow](#complete-data-flow)
3. [Simulation Workflow](#simulation-workflow)
4. [Observable Workflow](#observable-workflow)
5. [Cross-Referencing](#cross-referencing)
6. [Real-World Examples](#real-world-examples)
7. [Best Practices](#best-practices)

---

## Overview

This guide shows how **simulations**, **catalogs**, **queries**, and **observables** work together as an integrated system.

### The Big Picture

```
┌─────────────────────────────────────────────────────────────────┐
│                     TNCodebase Data Flow                         │
└─────────────────────────────────────────────────────────────────┘

1. RUN SIMULATION
   ├─ User creates config.json
   ├─ run_simulation_from_config(config)
   ├─ Simulation runs
   └─ Data saved to data/[algorithm]/[run_id]/

2. CATALOG UPDATED (Automatic!)
   ├─ Extract metadata from config
   ├─ Compute config hash
   ├─ Append to run_catalog.jsonl
   └─ Update runs_index.json

3. QUERY SIMULATIONS
   ├─ query("sim", filters...)
   ├─ Load catalog (fast!)
   ├─ Filter entries
   └─ Return matching runs

4. CALCULATE OBSERVABLES
   ├─ Reference simulation by run_id
   ├─ run_observable_calculation_from_config(config)
   ├─ Observable data saved
   └─ Observable catalog updated (automatic!)

5. QUERY OBSERVABLES
   ├─ query("obs", filters...)
   ├─ Load observable catalog
   ├─ Filter entries
   └─ Return matching observables

6. ANALYZE & PLOT
   ├─ Load actual data files
   ├─ Extract results
   ├─ Plot, analyze, compare
   └─ Publish!
```

---

## Complete Data Flow

### Phase 1: Simulation

```
User creates config
        ↓
run_simulation_from_config(config)
        ↓
┌───────────────────────────────────────┐
│ Check for existing run (hash check)   │
│   - Compute config hash                │
│   - Search catalog for hash            │
│   - If found & completed → skip        │
│   - If not found → proceed             │
└───────────────────────────────────────┘
        ↓
┌───────────────────────────────────────┐
│ Setup run directory                    │
│   - Generate run_id (timestamp + hash) │
│   - Create data/[algo]/[run_id]/      │
│   - Save config.json                   │
│   - Initialize metadata.json           │
└───────────────────────────────────────┘
        ↓
┌───────────────────────────────────────┐
│ Run simulation                         │
│   - Build Hamiltonian                  │
│   - Run algorithm (DMRG/ED/TDVP)       │
│   - Save results (sweep_*.jld2, etc)   │
└───────────────────────────────────────┘
        ↓
┌───────────────────────────────────────┐
│ Finalize & catalog                     │
│   - Update metadata.json (status)      │
│   - Extract catalog entry              │
│   - Append to run_catalog.jsonl        │
│   - Update runs_index.json             │
└───────────────────────────────────────┘
        ↓
Done! Simulation cataloged
```

### Phase 2: Query Simulations

```
User runs query()
        ↓
query("sim", algorithm="dmrg", N=20)
        ↓
┌───────────────────────────────────────┐
│ Load catalog                           │
│   - Read run_catalog.jsonl             │
│   - Parse each line as JSON            │
│   - Build array of entries             │
└───────────────────────────────────────┘
        ↓
┌───────────────────────────────────────┐
│ Filter entries                         │
│   - Check algorithm == "dmrg"          │
│   - Check N == 20                      │
│   - Keep matching entries              │
└───────────────────────────────────────┘
        ↓
┌───────────────────────────────────────┐
│ Tag results                            │
│   - Add _query_type = "simulation"    │
│   - Return Vector{Dict}                │
└───────────────────────────────────────┘
        ↓
Results ready!
        ↓
display_results(results)
get_run_ids(results)
load_config(results[1])
```

### Phase 3: Calculate Observables

```
User creates observable config
  (references simulation run_id)
        ↓
run_observable_calculation_from_config(config)
        ↓
┌───────────────────────────────────────┐
│ Find simulation                        │
│   - Extract sim_run_id from config    │
│   - Load simulation config             │
│   - Verify simulation exists           │
└───────────────────────────────────────┘
        ↓
┌───────────────────────────────────────┐
│ Check for existing calculation         │
│   - Compute observable config hash     │
│   - Search observable catalog          │
│   - If found → skip (unless force)     │
└───────────────────────────────────────┘
        ↓
┌───────────────────────────────────────┐
│ Setup observable directory             │
│   - Generate obs_run_id                │
│   - Create observables/[sim_algo]/     │
│     [sim_run_id]/[obs_run_id]/         │
│   - Save config.json                   │
└───────────────────────────────────────┘
        ↓
┌───────────────────────────────────────┐
│ Load simulation data                   │
│   - Load MPS sweeps (DMRG/TDVP)        │
│   - Or eigenstates (ED spectrum)       │
│   - Or time steps (ED time evolution)  │
└───────────────────────────────────────┘
        ↓
┌───────────────────────────────────────┐
│ Calculate observable                   │
│   - For each selected state/sweep/step │
│   - Compute observable value           │
│   - Store in array                     │
└───────────────────────────────────────┘
        ↓
┌───────────────────────────────────────┐
│ Save & catalog                         │
│   - Save observables.jld2              │
│   - Extract observable catalog entry   │
│   - Append to observables_catalog.jsonl│
└───────────────────────────────────────┘
        ↓
Done! Observable cataloged
```

### Phase 4: Query Observables

```
User runs query()
        ↓
query("obs", observable_type="entanglement_entropy")
        ↓
┌───────────────────────────────────────┐
│ Load observable catalog                │
│   - Read observables_catalog.jsonl     │
│   - Parse each line                    │
│   - Build array of entries             │
└───────────────────────────────────────┘
        ↓
┌───────────────────────────────────────┐
│ Filter entries                         │
│   - Check observable type              │
│   - Keep matching entries              │
└───────────────────────────────────────┘
        ↓
┌───────────────────────────────────────┐
│ Tag results                            │
│   - Add _query_type = "observable"    │
│   - Return Vector{Dict}                │
└───────────────────────────────────────┘
        ↓
Results ready!
        ↓
display_results(results)
get_run_ids(results)
load observable data
```

---

## Simulation Workflow

### Complete Example: DMRG Ground State

```julia
using TNCodebase
using JSON
using JLD2

# ═════════════════════════════════════════════════════════════════
# STEP 1: Create and Run Simulation
# ═════════════════════════════════════════════════════════════════

# Create config
config = Dict(
    "system" => Dict("type" => "spin", "N" => 20),
    "model" => Dict(
        "name" => "heisenberg",
        "params" => Dict("Jx" => 1.0, "Jy" => 1.0, "Jz" => 1.0)
    ),
    "state" => Dict("type" => "prebuilt", "name" => "neel"),
    "algorithm" => Dict(
        "type" => "dmrg",
        "options" => Dict("chi_max" => 100, "n_sweeps" => 50)
    )
)

# Run simulation
run_simulation_from_config(config)

# ═════════════════════════════════════════════════════════════════
# STEP 2: Query Results (Automatic Cataloging!)
# ═════════════════════════════════════════════════════════════════

# Query all DMRG runs for Heisenberg
results = query("sim", 
    algorithm="dmrg",
    model_name="heisenberg"
)

# Display results
display_results_compact(results)

# ═════════════════════════════════════════════════════════════════
# STEP 3: Extract Information
# ═════════════════════════════════════════════════════════════════

# Get the run we just created (latest)
latest_run = results[end]

# Extract run_id and directory
run_id = latest_run["run_id"]
run_dir = latest_run["run_dir"]

# Check ground state energy
E_ground = latest_run["results_summary"]["ground_energy"]
println("Ground state energy: $E_ground")

# ═════════════════════════════════════════════════════════════════
# STEP 4: Load Full Configuration
# ═════════════════════════════════════════════════════════════════

# Load complete config
full_config = load_config(latest_run)

# Check parameters
chi_max = full_config["algorithm"]["options"]["chi_max"]
println("Bond dimension used: $chi_max")

# ═════════════════════════════════════════════════════════════════
# STEP 5: Load Actual Data
# ═════════════════════════════════════════════════════════════════

# Load final MPS
final_sweep = latest_run["results_summary"]["sweeps_completed"]
mps_file = joinpath(run_dir, "sweep_$(lpad(final_sweep, 3, '0')).jld2")
data = load(mps_file)

psi = data["mps"]  # The actual MPS
E = data["energy"] # Energy at this sweep

# ═════════════════════════════════════════════════════════════════
# STEP 6: Calculate Observables (Next Section!)
# ═════════════════════════════════════════════════════════════════
```

**Key Points:**
- ✅ Catalog updated automatically after simulation
- ✅ Query finds run immediately
- ✅ Full metadata available without loading data
- ✅ Can extract run_id for observable calculations

---

## Observable Workflow

### Complete Example: Entanglement Entropy

```julia
using TNCodebase
using JLD2
using Plots

# ═════════════════════════════════════════════════════════════════
# STEP 1: Find Simulation to Analyze
# ═════════════════════════════════════════════════════════════════

# Query DMRG runs
sim_results = query("sim",
    algorithm="dmrg",
    model_name="heisenberg",
    N=20
)

# Get the run_id
sim_run_id = get_run_ids(sim_results)[1]
println("Analyzing simulation: $sim_run_id")

# ═════════════════════════════════════════════════════════════════
# STEP 2: Create Observable Config
# ═════════════════════════════════════════════════════════════════

# Load simulation config
sim_config = load_config(sim_results[1])

# Create observable config (references simulation)
obs_config = Dict(
    "simulation" => sim_config,  # Embed simulation config
    "observable" => Dict(
        "type" => "entanglement_entropy",
        "params" => Dict("bond" => 10)  # Cut at bond 10
    ),
    "analysis" => Dict(
        "sweep_selection" => Dict("type" => "last")  # Analyze last sweep
    )
)

# ═════════════════════════════════════════════════════════════════
# STEP 3: Run Observable Calculation
# ═════════════════════════════════════════════════════════════════

run_observable_calculation_from_config(obs_config)

# ═════════════════════════════════════════════════════════════════
# STEP 4: Query Observable Results
# ═════════════════════════════════════════════════════════════════

# Query by observable type
obs_results = query("obs",
    observable_type="entanglement_entropy",
    sim_algorithm="dmrg"
)

# Display
display_results(obs_results)

# Get latest calculation
latest_obs = obs_results[end]
obs_dir = latest_obs["obs_run_dir"]

# ═════════════════════════════════════════════════════════════════
# STEP 5: Load Observable Data
# ═════════════════════════════════════════════════════════════════

obs_data = load(joinpath(obs_dir, "observables.jld2"))

S = obs_data["entanglement_entropy"]  # Single value (last sweep)
bond = obs_data["bond"]                 # Bond number

println("Entanglement entropy at bond $bond: $S")

# ═════════════════════════════════════════════════════════════════
# STEP 6: Calculate Multiple Bonds
# ═════════════════════════════════════════════════════════════════

# Calculate for all bonds
entropies = Float64[]
bonds = 1:19  # For N=20 chain

for bond in bonds
    obs_config["observable"]["params"]["bond"] = bond
    run_observable_calculation_from_config(obs_config)
end

# Query all entanglement calculations for this simulation
all_obs = get_observables_for_simulation(sim_run_id)
entropy_obs = filter(o -> o["observable"]["type"] == "entanglement_entropy", all_obs)

# Load all and sort by bond
for obs in sort(entropy_obs, by=o->o["observable"]["params"]["bond"])
    obs_dir = obs["obs_run_dir"]
    data = load(joinpath(obs_dir, "observables.jld2"))
    push!(entropies, data["entanglement_entropy"])
end

# Plot entanglement profile
plot(1:19, entropies,
    xlabel="Bond position",
    ylabel="Entanglement entropy S",
    title="Entanglement Profile (Heisenberg N=20)",
    marker=:circle,
    lw=2
)
```

**Key Points:**
- ✅ Observable config references simulation
- ✅ Observable catalog updated automatically
- ✅ Can query observables independently
- ✅ Cross-reference simulation and observables

---

## Cross-Referencing

### Find Observables for a Simulation

```julia
# Method 1: Use helper function
sim_results = query("sim", algorithm="ed_spectrum", N=10)
sim_id = get_run_ids(sim_results)[1]

obs_results = get_observables_for_simulation(sim_id)
display_results(obs_results)

# Method 2: Query by simulation properties
obs_results = query("obs",
    sim_algorithm="ed_spectrum",
    sim_model_name="heisenberg"
)
```

### Find Simulation from Observable

```julia
# Query observable
obs_results = query("obs", observable_type="entanglement_entropy")

# Get simulation run_id
sim_run_id = obs_results[1]["sim_run_id"]

# Query simulation
sim_results = query("sim", run_id=sim_run_id)  # Not implemented yet!

# Alternative: extract from observable entry
sim_info = obs_results[1]["simulation"]
println("Simulation algorithm: $(sim_info["core"]["algorithm"])")
println("Model: $(sim_info["model"]["name"])")
```

### Compare Across Algorithms

```julia
# Same model, different algorithms
model = "heisenberg"
N = 10

# Run simulations
dmrg_results = query("sim", algorithm="dmrg", model_name=model, N=N)
ed_results = query("sim", algorithm="ed_spectrum", model_name=model, N=N)

# Calculate same observable for both
for results in [dmrg_results, ed_results]
    sim_config = load_config(results[1])
    obs_config = Dict(
        "simulation" => sim_config,
        "observable" => Dict("type" => "entanglement_entropy", "params" => Dict("bond" => 5)),
        "analysis" => Dict(
            "sweep_selection" => Dict("type" => "last"),  # DMRG
            "state_selection" => Dict("type" => "specific", "indices" => [1])  # ED (ground state)
        )
    )
    run_observable_calculation_from_config(obs_config)
end

# Query all entanglement calculations
all_obs = query("obs", observable_type="entanglement_entropy", observable_bond=5)

# Compare
for obs in all_obs
    algo = obs["simulation"]["core"]["algorithm"]
    S = load(joinpath(obs["obs_run_dir"], "observables.jld2"))["entanglement_entropy"]
    println("$algo: S = $S")
end
```

---

## Real-World Examples

### Example 1: Convergence Study

**Goal:** Study how ground state energy converges with bond dimension

```julia
# Run DMRG with different bond dimensions
bond_dims = [20, 50, 100, 200, 500]

for chi in bond_dims
    config = Dict(
        "system" => Dict("type" => "spin", "N" => 40),
        "model" => Dict("name" => "heisenberg", "params" => Dict("Jx" => 1.0, "Jy" => 1.0, "Jz" => 1.0)),
        "state" => Dict("type" => "random", "params" => Dict("bond_dim" => 10)),
        "algorithm" => Dict(
            "type" => "dmrg",
            "options" => Dict("chi_max" => chi, "n_sweeps" => 50)
        )
    )
    run_simulation_from_config(config)
end

# Query all runs
results = query("sim", algorithm="dmrg", model_name="heisenberg", N=40)

# Extract energies and bond dims
energies = [r["results_summary"]["ground_energy"] for r in results]
bond_dims_used = [r["algorithm_params"]["chi_max"] for r in results]

# Sort by bond dimension
perm = sortperm(bond_dims_used)
bond_dims_sorted = bond_dims_used[perm]
energies_sorted = energies[perm]

# Plot convergence
using Plots
plot(bond_dims_sorted, energies_sorted,
    xlabel="χ_max",
    ylabel="Ground state energy",
    title="Energy Convergence vs Bond Dimension",
    marker=:circle,
    xscale=:log10
)
```

### Example 2: Model Comparison

**Goal:** Compare ground state properties across different models

```julia
# Run simulations for multiple models
models = ["heisenberg", "transverse_field_ising", "xxz"]

for model in models
    config = Dict(
        "system" => Dict("type" => "spin", "N" => 20),
        "model" => Dict("name" => model, "params" => Dict("Jx" => 1.0, "Jz" => 1.0)),
        "state" => Dict("type" => "prebuilt", "name" => "neel"),
        "algorithm" => Dict("type" => "dmrg", "options" => Dict("chi_max" => 100, "n_sweeps" => 50))
    )
    run_simulation_from_config(config)
end

# Query each model
for model in models
    results = query("sim", algorithm="dmrg", model_name=model, N=20)
    E = results[1]["results_summary"]["ground_energy"]
    println("$model: E₀ = $E")
end
```

### Example 3: Time Evolution Analysis

**Goal:** Track magnetization decay over time

```julia
# Run time evolution
config = Dict(
    "system" => Dict("type" => "spin", "N" => 10),
    "model" => Dict("name" => "heisenberg", "params" => Dict("Jx" => 1.0, "Jy" => 1.0, "Jz" => 1.0)),
    "state" => Dict("type" => "prebuilt", "name" => "polarized", "params" => Dict("spin_direction" => "Z")),
    "algorithm" => Dict("type" => "ed_time_evolution", "dt" => 0.05, "n_steps" => 200)
)
run_simulation_from_config(config)

# Query time evolution runs
results = query("sim", algorithm="ed_time_evolution")
sim_config = load_config(results[1])

# Calculate magnetization at all times
obs_config = Dict(
    "simulation" => sim_config,
    "observable" => Dict("type" => "magnetization", "params" => Dict("operator" => "Z", "site" => 1)),
    "analysis" => Dict("step_selection" => Dict("type" => "all"))
)
run_observable_calculation_from_config(obs_config)

# Load and plot
obs_results = query("obs", observable_type="magnetization", sim_algorithm="ed_time_evolution")
obs_data = load(joinpath(obs_results[1]["obs_run_dir"], "observables.jld2"))

times = obs_data["times"]
magnetization = obs_data["magnetization"]

plot(times, magnetization,
    xlabel="Time t",
    ylabel="⟨σᶻ₁⟩",
    title="Magnetization Decay",
    lw=2
)
```

---

## Best Practices

### 1. Always Use Catalogs

**❌ Don't:**
```julia
# Manually scanning directories
for dir in readdir("data/dmrg")
    config = JSON.parsefile(joinpath("data/dmrg", dir, "config.json"))
    if config["model"]["name"] == "heisenberg"
        # Process...
    end
end
```

**✅ Do:**
```julia
# Use catalog query
results = query("sim", algorithm="dmrg", model_name="heisenberg")
```

### 2. Use Query Builder for Exploration

**Start with HTML builder:**
```julia
build_query("sim")  # Explore what's available
```

**Then refine in code:**
```julia
results = query("sim", algorithm="dmrg", N_gte=20)
```

### 3. Load Configs Before Observable Calculations

**Always reference the simulation config:**
```julia
# Load simulation config
sim_results = query("sim", algorithm="dmrg")
sim_config = load_config(sim_results[1])

# Reference it in observable config
obs_config = Dict(
    "simulation" => sim_config,  # ← Important!
    "observable" => Dict(...)
)
```

### 4. Use Helper Functions

**Extract IDs cleanly:**
```julia
# ✅ Clean
ids = get_run_ids(results)

# ❌ Messy
ids = [r["run_id"] for r in results]
```

### 5. Check Catalog Summary First

**Before querying, know what's there:**
```julia
catalog_summary("sim")  # See what algorithms, models exist
results = query("sim", algorithm="dmrg")  # Then query
```

### 6. Handle Empty Results

**Always check:**
```julia
results = query("sim", algorithm="some_algo")

if isempty(results)
    println("No results found!")
else
    display_results(results)
end
```

### 7. Use Compact Display for Large Sets

**For many results:**
```julia
results = query("sim", status="completed")  # Could be 100s

# Use compact view
display_results_compact(results)

# Or paginate
for i in 1:10:length(results)
    display_results(results[i:min(i+9, end)])
end
```

### 8. Cross-Reference Systematically

**Link simulations and observables:**
```julia
# 1. Query simulation
sim_results = query("sim", algorithm="ed_spectrum", N=10)
sim_id = get_run_ids(sim_results)[1]

# 2. Calculate observable
sim_config = load_config(sim_results[1])
obs_config = Dict("simulation" => sim_config, ...)
run_observable_calculation_from_config(obs_config)

# 3. Query observable (verify it's there)
obs_results = get_observables_for_simulation(sim_id)
display_results(obs_results)
```

---

## Summary

The integrated system provides:

✅ **Automatic cataloging** - Happens during simulation/observable runs  
✅ **Fast queries** - Metadata indexed in catalogs  
✅ **Type safety** - Metadata tagging for auto-detection  
✅ **Cross-referencing** - Observables link to simulations  
✅ **Complete workflow** - Run → catalog → query → analyze  
✅ **Reproducibility** - Config hashing prevents duplicates  
✅ **Extensibility** - Easy to add new query filters

**Complete cycle:**
```
Config → Run → Catalog → Query → Load → Analyze → Publish
  ↑                                                    ↓
  └────────────────────────────────────────────────────┘
           Iterate, refine, repeat!
```

**Next:** See DEVELOPER_GUIDE.md for extending the system!
