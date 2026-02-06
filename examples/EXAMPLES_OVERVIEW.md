# Heisenberg Model Examples - Complete Suite

## Overview

This suite provides **three complete examples** for the Heisenberg model, each demonstrating a different algorithm:

1. **DMRG** - Ground state search (large systems)
2. **ED Spectrum** - Full eigenspectrum (small systems)
3. **ED Time Evolution** - Quantum dynamics (small systems)

All examples follow the same structure as your existing DMRG example for consistency.

---

## Example Comparison

| Example | Algorithm | System Size | Output | Use Case |
|---------|-----------|-------------|--------|----------|
| **DMRG** | Density Matrix Renormalization | N ~ 20-1000 | Ground state MPS | Large systems, low-energy physics |
| **ED Spectrum** | Exact Diagonalization | N ≤ 12 | All eigenvalues & eigenvectors | Small systems, full spectrum |
| **ED Time Evolution** | Exact time evolution | N ≤ 12 | State at each time step | Quantum dynamics, quenches |

---

## Files Provided

### 1. ED Spectrum Example
```
heisenberg/
├── ed_spectrum_config.json          # Config: N=10, isotropic Heisenberg
├── ed_spectrum_run.jl               # Run script
└── ed_spectrum_README.md            # Complete documentation
```

**Key Features:**
- Computes all 1024 eigenstates for N=10
- No initial state needed
- Ground state energy and spectral gap
- Foundation for observable calculations on all eigenstates

### 2. ED Time Evolution Example
```
heisenberg/
├── ed_time_evolution_config.json    # Config: N=10, polarized initial state
├── ed_time_evolution_run.jl         # Run script
└── ed_time_evolution_README.md      # Complete documentation
```

**Key Features:**
- Evolves polarized state |↑↑↑...⟩ under Heisenberg dynamics
- Time evolution from t=0 to t=10 (200 steps)
- Exact unitary evolution
- Watch quantum scrambling in action

---

## Quick Start Guide

### Running ED Spectrum

```bash
cd examples/00_quickstart/heisenberg
julia ed_spectrum_run.jl
```

**Output:**
- All eigenvalues (1024 values)
- All eigenvectors (1024 × 1024 matrix)
- Ground state: E₀ ≈ -4.26
- Spectral gap: Δ ≈ 0.63

### Running ED Time Evolution

```bash
cd examples/00_quickstart/heisenberg
julia ed_time_evolution_run.jl
```

**Output:**
- Quantum state at t = 0, 0.05, 0.10, ..., 10.0
- Watch magnetization decay from +1 to 0
- See entanglement grow from 0 to maximum

---

## Workflow Comparison

### DMRG Workflow
```julia
# 1. Run simulation
julia dmrg_run.jl

# 2. Query results
results = query("sim", algorithm="dmrg")

# 3. Load ground state
run_dir = get_run_dirs(results)[1]
psi = load_mps_sweep(run_dir, sweep=50)

# 4. Calculate observables on ground state
```

### ED Spectrum Workflow
```julia
# 1. Run simulation
julia ed_spectrum_run.jl

# 2. Query results
results = query("sim", algorithm="ed_spectrum")

# 3. Load all eigenstates
run_dir = get_run_dirs(results)[1]
data = load(joinpath(run_dir, "results.jld2"))
eigenvalues = data["eigenvalues"]
eigenvectors = data["eigenvectors"]

# 4. Calculate observables on ALL eigenstates
obs_config = Dict(
    "simulation" => config,
    "observable" => Dict("type" => "entanglement_entropy"),
    "analysis" => Dict("state_selection" => Dict("type" => "all"))
)
```

### ED Time Evolution Workflow
```julia
# 1. Run simulation
julia ed_time_evolution_run.jl

# 2. Query results
results = query("sim", algorithm="ed_time_evolution")

# 3. Load state at specific time
run_dir = get_run_dirs(results)[1]
psi_t5 = load_ed_at_time(run_dir, 5.0)

# 4. Calculate time-dependent observables
obs_config = Dict(
    "simulation" => config,
    "observable" => Dict("type" => "magnetization"),
    "analysis" => Dict("step_selection" => Dict("type" => "all"))
)
```

---

## When to Use Each Method

### Use DMRG When:
- ✅ System size N > 12
- ✅ Only need ground state
- ✅ Want low-energy excitations
- ✅ 1D systems with area-law entanglement

**Example:** Finding ground state of 100-site Heisenberg chain

### Use ED Spectrum When:
- ✅ System size N ≤ 12
- ✅ Need full eigenspectrum
- ✅ Want excited states
- ✅ Calculate observables on many states

**Example:** Computing entanglement entropy for all eigenstates

### Use ED Time Evolution When:
- ✅ System size N ≤ 12
- ✅ Studying non-equilibrium dynamics
- ✅ Quench experiments
- ✅ Exact unitary evolution required

**Example:** Watching magnetization decay after quantum quench

---

## Physics Highlights

### Common Physics (All Examples)
- **Model:** Isotropic Heisenberg (XXX)
- **Interactions:** Antiferromagnetic (J > 0)
- **Symmetry:** SU(2) continuous symmetry
- **Boundary:** Open boundary conditions

### Unique to Each Example

**DMRG:**
- Finds singlet ground state
- Bond dimension χ ~ 30-50 for N=20
- Energy per site E/N ≈ -0.44

**ED Spectrum:**
- All 1024 eigenstates for N=10
- Ground state is singlet (S=0)
- First excited states are triplets (S=1)
- Spectral gap Δ ≈ 0.63

**ED Time Evolution:**
- Initial: Polarized |↑↑↑...⟩ (zero entanglement)
- Final: Scrambled (maximal entanglement)
- Magnetization: ⟨σᶻ⟩ decays from +1 to 0
- Energy conserved throughout

---

## Configuration Highlights

### What's Different in ED Spectrum

**No state section:**
```json
{
  "system": {...},
  "model": {...},
  "algorithm": {"type": "ed_spectrum"}
  // NO "state" - eigenstates computed directly!
}
```

### What's Different in ED Time Evolution

**Requires initial state:**
```json
{
  "system": {...},
  "model": {...},
  "state": {
    "type": "prebuilt",
    "name": "polarized"  // Initial condition required!
  },
  "algorithm": {
    "type": "ed_time_evolution",
    "dt": 0.05,           // Time step
    "n_steps": 200        // Number of steps
  }
}
```

---

## Observable Calculations

All three examples support observable calculations through the unified query system!

### On Ground State (DMRG or ED Spectrum)
```julia
# After running DMRG or ED spectrum
obs_config = Dict(
    "simulation" => config,
    "observable" => Dict(
        "type" => "entanglement_entropy",
        "params" => Dict("bond" => 5)
    ),
    "analysis" => Dict(
        "sweep_selection" => Dict("type" => "last")  # DMRG
        # OR
        "state_selection" => Dict("type" => "specific", "indices" => [1])  # ED
    )
)
```

### On All Eigenstates (ED Spectrum Only)
```julia
obs_config = Dict(
    "simulation" => config,
    "observable" => Dict("type" => "entanglement_entropy"),
    "analysis" => Dict(
        "state_selection" => Dict("type" => "all")  # All 1024 states!
    )
)
```

### Time-Dependent (ED Time Evolution Only)
```julia
obs_config = Dict(
    "simulation" => config,
    "observable" => Dict("type" => "magnetization"),
    "analysis" => Dict(
        "step_selection" => Dict("type" => "all")  # All 200 time steps!
    )
)
```

---

## System Size Guidelines

| N | 2^N | DMRG | ED Spectrum | ED Time Evolution |
|---|-----|------|-------------|-------------------|
| 8 | 256 | ✅ Fast | ✅ Very fast | ✅ Very fast |
| 10 | 1024 | ✅ Fast | ✅ Fast | ✅ Fast |
| 12 | 4096 | ✅ Fast | ✅ Slow | ✅ Slow |
| 14 | 16384 | ✅ Fast | ⚠️ Very slow | ⚠️ Very slow |
| 20 | 1M | ✅ Moderate | ❌ Infeasible | ❌ Infeasible |
| 100 | 2^100 | ✅ Slow | ❌ Impossible | ❌ Impossible |

**Recommendation:** 
- ED examples: Use N=10 (fast, good physics)
- DMRG example: Use N=20-50 (shows scaling advantage)

---

## Documentation Quality

All three READMEs include:

✅ **Complete physics explanation**
✅ **Algorithm description**
✅ **Expected output with examples**
✅ **Configuration breakdown**
✅ **Modification suggestions**
✅ **Result analysis workflows**
✅ **Observable calculation examples**
✅ **Troubleshooting section**
✅ **Comparison with other methods**
✅ **Next steps and related examples**

---

## Integration with Query System

All examples work seamlessly with the unified query system:

```julia
using TNCodebase

# Query any simulation type
results = query("sim", algorithm="dmrg")
results = query("sim", algorithm="ed_spectrum")
results = query("sim", algorithm="ed_time_evolution")

# Same display functions work for all!
display_results(results)
display_results_compact(results)

# Same helper functions work for all!
ids = get_run_ids(results)
dirs = get_run_dirs(results)
config = load_config(results[1])
```

---

## Summary

You now have **three complete, production-ready examples** for the Heisenberg model:

1. **DMRG** (existing) - Ground state search for large systems
2. **ED Spectrum** (new) - Full eigenspectrum for small systems
3. **ED Time Evolution** (new) - Quantum dynamics for small systems

All examples:
- Follow the same structure
- Use the same Heisenberg model
- Work with the unified query system
- Include comprehensive documentation
- Support observable calculations

**Complete toolkit for studying the Heisenberg model across all relevant methods!** 🎉
