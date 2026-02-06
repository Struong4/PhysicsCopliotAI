# Heisenberg Model: ED Time Evolution Example

## Overview

This example demonstrates **exact time evolution** of a quantum state under the Heisenberg Hamiltonian:
- ✅ Start from polarized initial state (all spins up)
- ✅ Evolve under Heisenberg dynamics
- ✅ Exact unitary evolution (no approximations)
- ✅ Track quantum state at each time step
- ✅ Foundation for calculating time-dependent observables

**Complexity:** Intermediate  
**Prerequisites:** Package installed and activated  
**System Size Limit:** N ≤ 12 (due to exponential state space)

---

## What This Example Does

### Physics

Evolves an **initial polarized state** under the Heisenberg Hamiltonian:

```
|ψ(0)⟩ = |↑↑↑↑↑↑↑↑↑↑⟩  (all spins pointing up)

|ψ(t)⟩ = exp(-iHt) |ψ(0)⟩  (unitary evolution)

H = Jx Σᵢ σˣᵢσˣᵢ₊₁ + Jy Σᵢ σʸᵢσʸᵢ₊₁ + Jz Σᵢ σᶻᵢσᶻᵢ₊₁
```

**Physical interpretation:**
- **Initial state:** Product state, no entanglement
- **Evolution:** Antiferromagnetic interactions spread correlations
- **Final state:** Highly entangled, delocalized
- **Dynamics:** Spin diffusion, magnetization decay

**Our parameters:**
- N = 10 sites
- Isotropic Heisenberg (Jx = Jy = Jz = 1.0)
- Time step dt = 0.05
- Total time T = 10.0 (200 steps)

### Algorithm

Uses **Exact Time Evolution** via matrix exponential:

1. Build Hamiltonian H (1024 × 1024 matrix)
2. Compute time evolution operator U(dt) = exp(-iH dt)
3. Apply U repeatedly: |ψₙ₊₁⟩ = U(dt) |ψₙ⟩
4. Save state at each time step

**What you get:**
- **State at t=0:** Initial polarized state
- **State at t=0.05:** After one time step
- **State at t=0.10:** After two time steps
- ...
- **State at t=10.0:** Final evolved state (200 steps)

**Computational cost:**
- Hamiltonian: O(2^N × 2^N) memory
- Time evolution operator: O(2^3N) to compute once
- Each step: O(2^2N) matrix-vector multiply
- Total: ~1-5 seconds for N=10, 200 steps

---

## Files

```
heisenberg/
├── ed_time_evolution_README.md       # This file
├── ed_time_evolution_config.json     # All simulation parameters
└── ed_time_evolution_run.jl          # Main script
```

---

## Usage

### Quick Start

```bash
# Navigate to this directory
cd examples/00_quickstart/heisenberg

# Run the example
julia ed_time_evolution_run.jl
```

The script will:
1. Load configuration from `ed_time_evolution_config.json`
2. Build the Heisenberg Hamiltonian
3. Create initial polarized state |↑↑↑↑↑↑↑↑↑↑⟩
4. Evolve for 200 time steps (t = 0 to t = 10.0)
5. Save state at each time step to `data/ed_time_evolution/`

### Expected Output

```
======================================================================
Heisenberg Model: ED Time Evolution
======================================================================

📋 Configuration loaded from: ed_time_evolution_config.json

   System: spin chain
   N sites: 10
   Model: heisenberg
   Initial state: polarized (Z-polarized)

⏱️  Time evolution:
   Time step dt: 0.05
   Number of steps: 200
   Total time: 10.0

🚀 Starting time evolution...

======================================================================
Starting ED Simulation: ED_TIME_EVOLUTION
======================================================================

[1/5] Checking for existing runs...
  No completed run found. Proceeding...

[2/5] Setting up database...
✓ Setup complete: data/ed_time_evolution/20260206_125411_b7f9e234

[3/5] Building Hamiltonian...
  ✓ Hamiltonian: 1024 × 1024
  ✓ Time evolution operator computed

[4/5] Running simulation...
======================================================================
  Initial state: polarized (Z-direction)
  
  Time evolution progress:
  ✓ Step 50/200 (t = 2.50)
  ✓ Step 100/200 (t = 5.00)
  ✓ Step 150/200 (t = 7.50)
  ✓ Step 200/200 (t = 10.00)
  
  Evolution complete!
======================================================================

[5/5] Finalizing...
  ✓ Run finalized with status: completed
  ✓ Appended to catalog

✅ Time evolution complete!
```

---

## Understanding the Configuration

### 1. System
```json
"system": {
  "type": "spin",
  "N": 10
}
```
- 10 spin-1/2 sites
- State space dimension: 2^10 = 1024

### 2. Model
```json
"model": {
  "name": "heisenberg",
  "params": {
    "Jx": 1.0,
    "Jy": 1.0,
    "Jz": 1.0,
    "dtype": "ComplexF64"
  }
}
```
- Isotropic Heisenberg
- ComplexF64 required for time evolution

### 3. Initial State (REQUIRED!)
```json
"state": {
  "type": "prebuilt",
  "name": "polarized",
  "params": {
    "spin_direction": "Z",
    "eigenstate": 1
  }
}
```
- **polarized:** All spins aligned
- **Z-direction:** Pointing up (|↑↑↑...⟩)
- **eigenstate: 1:** Spin up (2 = spin down)

**Unlike ED spectrum, time evolution REQUIRES an initial state!**

### 4. Time Evolution Parameters
```json
"algorithm": {
  "type": "ed_time_evolution",
  "dt": 0.05,
  "n_steps": 200
}
```
- **dt:** Time step size (smaller = more accurate, slower)
- **n_steps:** Number of steps
- **Total time:** dt × n_steps = 10.0

**Time step choice:**
- Too large: Evolution becomes inaccurate
- Too small: Unnecessarily slow
- Good rule: dt ~ 0.05 / max(|Jx|, |Jy|, |Jz|)

---

## Modifying the Example

### Initial State Variations

**1. Néel state (alternating spins):**
```json
"state": {
  "type": "prebuilt",
  "name": "neel"
}
```
- |↑↓↑↓↑↓↑↓↑↓⟩
- Classical antiferromagnetic order
- Watch it melt under quantum dynamics!

**2. Domain wall:**
```json
"state": {
  "type": "prebuilt",
  "name": "domain_wall"
}
```
- |↑↑↑↑↑↓↓↓↓↓⟩
- Half up, half down
- Watch domain spread and disappear

**3. Random product state:**
```json
"state": {
  "type": "random"
}
```
- Random spins on each site
- No initial entanglement

### Time Evolution Settings

**Longer evolution:**
```json
"dt": 0.05,
"n_steps": 400
```
- Total time: 20.0
- See long-time behavior

**Finer resolution:**
```json
"dt": 0.01,
"n_steps": 1000
```
- Total time: 10.0 (same)
- More accurate, smoother curves

**Shorter (for testing):**
```json
"dt": 0.1,
"n_steps": 50
```
- Total time: 5.0
- Quick test run

### Model Variations

**1. Add transverse field:**
```json
"hx": 0.5
```
- Breaks Z-symmetry
- Causes precession

**2. XXZ anisotropy:**
```json
"Jz": 2.0
```
- Prefer Z-alignment
- Slower relaxation

---

## Working with Results

### 1. Query Time Evolution Runs

```julia
using TNCodebase

# Find time evolution runs
results = query("sim", algorithm="ed_time_evolution")
display_results(results)

# Get run directory
run_id = get_run_ids(results)[1]
run_dir = get_run_dirs(results)[1]
```

### 2. Load State at Specific Time

```julia
using JLD2

# Load state at t = 5.0
time_index = 100  # Since dt = 0.05, step 100 is t = 5.0
state_file = joinpath(run_dir, "step_$(lpad(time_index, 3, '0')).jld2")
data = load(state_file)

psi = data["state"]      # Quantum state vector (1024 elements)
time = data["time"]      # Should be 5.0
```

### 3. Calculate Time-Dependent Observables

After running time evolution, calculate observables at all times:

```julia
# Config for time-dependent magnetization
obs_config = Dict(
    "simulation" => config,
    "observable" => Dict(
        "type" => "magnetization",
        "params" => Dict(
            "operator" => "Z",
            "site" => 1
        )
    ),
    "analysis" => Dict(
        "step_selection" => Dict("type" => "all")
    )
)

run_observable_calculation_from_config(obs_config)
```

### 4. Load and Plot Time Series

```julia
# Query observable results
obs_results = query("obs",
    observable_type="magnetization",
    sim_algorithm="ed_time_evolution"
)

# Load magnetization data
obs_dir = get_run_dirs(obs_results)[1]
obs_data = load(joinpath(obs_dir, "observables.jld2"))

times = obs_data["times"]           # [0.0, 0.05, 0.1, ..., 10.0]
magnetization = obs_data["magnetization"]  # ⟨Z₁(t)⟩ at each time

# Plot dynamics
using Plots
plot(times, magnetization,
    xlabel="Time t",
    ylabel="⟨σᶻ₁⟩",
    title="Magnetization Decay (Heisenberg, N=10)",
    lw=2
)
```

---

## Physics of the Dynamics

### What Happens During Evolution?

**Initial state (t=0):**
```
|ψ⟩ = |↑↑↑↑↑↑↑↑↑↑⟩
⟨σᶻᵢ⟩ = +1  (all spins up)
Entanglement = 0  (product state)
```

**Early time (t ~ 1):**
```
Heisenberg interactions create local spin flips
Adjacent spins start to correlate
Magnetization begins to decrease
Entanglement grows from boundaries
```

**Intermediate time (t ~ 5):**
```
Correlations spread across chain
Magnetization decays toward zero
State becomes highly entangled
No longer resembles initial state
```

**Long time (t ~ 10):**
```
⟨σᶻᵢ⟩ ≈ 0  (no net magnetization)
System has "thermalized" locally
Entanglement saturated
State is maximally scrambled
```

### Why Does Magnetization Decay?

The Heisenberg Hamiltonian has **SU(2) symmetry**:
- Conserves total spin: Sᵗᵒᵗ = Σᵢ Sᵢ
- Does NOT conserve Sᶻᵗᵒᵗ (or Sˣᵗᵒᵗ, Sʸᵗᵒᵗ)
- Initial state has Sᶻᵗᵒᵗ = N/2 = 5
- But individual ⟨σᶻᵢ⟩ can change!

Result: Local magnetization spreads and dephases, while total spin stays constant.

### Quantum Scrambling

- Initial state has **zero entanglement** (product state)
- Final state has **maximal entanglement** (volume-law)
- Information has **scrambled** across the chain
- Cannot distinguish from thermal ensemble locally

---

## Time Evolution vs Eigenspectrum

| Property | Time Evolution | Eigenspectrum |
|----------|---------------|---------------|
| **Initial state** | Required | Not needed |
| **Output** | States at times | All eigenstates |
| **Use case** | Dynamics | Spectrum |
| **Observables** | Time-dependent | Energy-dependent |
| **Best for** | Quench dynamics | Thermodynamics |

**Use time evolution when:**
- Studying non-equilibrium dynamics
- Quench experiments
- Time-dependent phenomena
- Quantum scrambling

**Use eigenspectrum when:**
- Want all energy eigenstates
- Studying spectrum structure
- Equilibrium properties
- Thermal ensembles

---

## Observable Calculations

### Magnetization Dynamics

```julia
# Calculate ⟨σᶻ₁(t)⟩ at all times
obs_config = Dict(
    "simulation" => config,
    "observable" => Dict(
        "type" => "magnetization",
        "params" => Dict("operator" => "Z", "site" => 1)
    ),
    "analysis" => Dict("step_selection" => Dict("type" => "all"))
)
```

### Correlation Function Spreading

```julia
# Calculate ⟨σᶻ₁ σᶻᵢ(t)⟩ for all sites i
obs_config = Dict(
    "simulation" => config,
    "observable" => Dict(
        "type" => "correlation_function",
        "params" => Dict("operator" => "Z", "sites" => (1, 5))
    ),
    "analysis" => Dict("step_selection" => Dict("type" => "all"))
)
```

### Entanglement Growth

```julia
# Calculate S(bond, t) - entanglement entropy vs time
obs_config = Dict(
    "simulation" => config,
    "observable" => Dict(
        "type" => "entanglement_entropy",
        "params" => Dict("bond" => 5)
    ),
    "analysis" => Dict("step_selection" => Dict("type" => "all"))
)
```

---

## Advanced: Energy Conservation Check

Since evolution is exact and unitary, **energy should be conserved**:

```julia
# Calculate ⟨H⟩(t) at all times
obs_config = Dict(
    "simulation" => config,
    "observable" => Dict(
        "type" => "energy"
    ),
    "analysis" => Dict("step_selection" => Dict("type" => "all"))
)

run_observable_calculation_from_config(obs_config)

# Load and verify
obs_results = query("obs", observable_type="energy")
obs_data = load(joinpath(get_run_dirs(obs_results)[1], "observables.jld2"))

energies = obs_data["energy"]
println("Energy variance: ", std(energies))  # Should be ~0!
```

---

## Troubleshooting

### Issue: Evolution becomes inaccurate

**Symptom:** Energy not conserved, oscillations grow

**Cause:** Time step dt too large

**Solution:** Reduce dt to 0.01 or smaller

### Issue: Slow execution

**Symptom:** Taking minutes for 200 steps

**Cause:** System size too large (N > 12)

**Solutions:**
1. Reduce N to 10 or 11
2. Reduce n_steps for testing
3. Use coarser dt temporarily

### Issue: Out of memory

**Cause:** N > 12, state space too large

**Solution:** Reduce N. ED is limited to ~N=12 maximum.

---

## Comparison with TDVP

For larger systems, use **Time-Dependent Variational Principle (TDVP)**:

| Method | ED Time Evolution | TDVP |
|--------|------------------|------|
| **System size** | N ≤ 12 | N ~ 100-1000 |
| **Accuracy** | Exact | Approximate (MPS) |
| **Time step** | Fixed dt | Adaptive |
| **Memory** | O(4^N) | O(Nχ²) |
| **Best for** | Small, exact | Large, approximate |

---

## Next Steps

After running time evolution:

1. **Calculate observables:**
   - Magnetization decay
   - Correlation spreading
   - Entanglement growth

2. **Vary initial states:**
   - Try Néel state
   - Try domain wall
   - Compare relaxation rates

3. **Explore models:**
   - XXZ anisotropy
   - Add transverse field
   - Long-range interactions

4. **Compare methods:**
   - Run TDVP on same system
   - Verify TDVP matches ED for small N
   - Extend TDVP to larger N

---

## See Also

**Related Examples:**
- `heisenberg_ed_spectrum_README.md` - Compute eigenspectrum
- `heisenberg_dmrg_README.md` - Ground state search
- `examples/time_evolution/tdvp/` - TDVP for large systems

**Documentation:**
- `docs/time_evolution.md` - Time evolution methods
- `docs/observables.md` - Observable calculations

---

## Summary

This example demonstrates:

✅ **Exact time evolution** - No approximations  
✅ **Quantum dynamics** - From polarized to entangled state  
✅ **Magnetization decay** - Watch symmetry breaking disappear  
✅ **Observable calculations** - Track time-dependent quantities  
✅ **Energy conservation** - Verify unitarity

**You've successfully run quantum time evolution with ED!**

**Physics insight:** Even a simple polarized state evolves into a complex, highly entangled state under Heisenberg dynamics - quantum scrambling in action! 🌀
