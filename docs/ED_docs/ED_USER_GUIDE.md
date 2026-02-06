# EXACT DIAGONALIZATION (ED) - USER GUIDE

## 📋 Table of Contents
1. [Overview](#overview)
2. [What is Exact Diagonalization?](#what-is-exact-diagonalization)
3. [When to Use ED](#when-to-use-ed)
4. [System Size Limits](#system-size-limits)
5. [ED Spectrum](#ed-spectrum)
6. [ED Time Evolution](#ed-time-evolution)
7. [Observable Calculations](#observable-calculations)
8. [Complete Workflows](#complete-workflows)
9. [Performance Tips](#performance-tips)
10. [Comparison with Other Methods](#comparison-with-other-methods)

---

## Overview

**Exact Diagonalization (ED)** is a computational method that solves quantum many-body problems by directly diagonalizing the Hamiltonian matrix in the full Hilbert space.

### Key Features

✅ **Numerically exact** - No approximations (within machine precision)  
✅ **Complete spectrum** - Can compute all eigenstates  
✅ **Exact time evolution** - Unitary evolution with no truncation  
✅ **Small to medium systems** - N ≤ 14 for spin-1/2, varies by system  
✅ **Benchmark quality** - Gold standard for validating other methods  
✅ **Observable calculations** - On any eigenstate or time step

### What TNCodebase ED Supports

**Algorithms:**
- Ground state search
- Full spectrum diagonalization
- Exact time evolution

**Systems:**
- Spin systems (S=1/2, S=1, arbitrary S)
- Boson systems
- Spin-boson coupled systems

**Models:**
- Transverse Field Ising (TFI)
- Heisenberg (XXX, XXZ, XYZ)
- Long-Range Ising (exact power-law)
- Ising-Dicke (spin-boson)
- Custom models

---

## What is Exact Diagonalization?

### The Basic Idea

**Problem:** Solve quantum Hamiltonian H|ψ⟩ = E|ψ⟩

**ED Approach:**
1. Write H as a matrix in the full Hilbert space
2. Diagonalize: H = V D V†
3. Eigenvectors V[:,i] are energy eigenstates
4. Eigenvalues D[i,i] are energy levels

**Example: N=3 spins**
```
Hilbert space dimension: 2³ = 8
Hamiltonian: 8 × 8 matrix
Diagonalization gives:
  - 8 eigenstates |ψ₀⟩, |ψ₁⟩, ..., |ψ₇⟩
  - 8 energies E₀ < E₁ < ... < E₇
```

### Why "Exact"?

- **No truncation** - Full Hilbert space retained
- **No approximation** - Only numerical round-off errors
- **All eigenstates** - Can compute entire spectrum
- **Unitary evolution** - Exact exp(-iHt) for time dynamics

### The Cost

**Memory:** O(D²) where D = Hilbert space dimension
```
Spin-1/2:  D = 2^N
N=10:  D = 1,024      → ~8 MB
N=12:  D = 4,096      → ~128 MB
N=14:  D = 16,384     → ~2 GB
N=16:  D = 65,536     → ~32 GB (impractical)
```

**Time:** O(D³) for full diagonalization
```
N=10:  ~1 second
N=12:  ~1 minute
N=14:  ~30 minutes
N=16:  ~hours (if memory allows)
```

---

## When to Use ED

### ✅ Use ED When:

**1. System size is small (N ≤ 12-14)**
```julia
# Perfect for ED
config = Dict(
    "system" => Dict("type" => "spin", "N" => 10),
    "algorithm" => Dict("type" => "ed_spectrum")
)
```

**2. You need the full eigenspectrum**
```julia
# ED gives ALL 1024 eigenstates for N=10
results = query("sim", algorithm="ed_spectrum", N=10)
# Now calculate observables on every eigenstate!
```

**3. You need exact results (benchmarking)**
```julia
# Compare DMRG ground state energy with ED
ed_E0 = ed_results[1]["results_summary"]["ground_energy"]
dmrg_E0 = dmrg_results[1]["results_summary"]["ground_energy"]
error = abs(ed_E0 - dmrg_E0)
println("DMRG error: $error")  # Benchmark DMRG accuracy
```

**4. You want exact time evolution**
```julia
# No Trotter errors, no MPS truncation
config = Dict(
    "system" => Dict("type" => "spin", "N" => 10),
    "algorithm" => Dict("type" => "ed_time_evolution", "dt" => 0.01, "n_steps" => 1000)
)
# Exact evolution for 10 time units
```

**5. You're studying excited states**
```julia
# ED naturally gives excited states
# DMRG only gets ground state (mostly)
energies = ed_results[1]["eigenvalues"]
spectral_gap = energies[2] - energies[1]
```

**6. You want to understand spectral properties**
```julia
# Full density of states
# Level statistics
# Spectral gaps
# Entanglement vs energy
```

### ❌ Don't Use ED When:

**1. System size is large (N > 14)**
```julia
# BAD - will crash or take forever
config = Dict(
    "system" => Dict("type" => "spin", "N" => 20),  # 2^20 = 1M states!
    "algorithm" => Dict("type" => "ed_spectrum")
)
# Use DMRG instead
```

**2. You only need ground state of large system**
```julia
# ED is overkill for just ground state
# Use DMRG which scales to N~100-1000
```

**3. You're studying 2D or 3D systems**
```julia
# 2D: Even 4×4 lattice is too large for ED
# Use DMRG or PEPS
```

---

## System Size Limits

### Practical Limits

| System Type | Max N (Practical) | Hilbert Dim | Memory | Time |
|-------------|-------------------|-------------|--------|------|
| **Spin-1/2** | 12-13 | 4,096-8,192 | ~130 MB-1 GB | ~1-10 min |
| **Spin-1** | 9-10 | 19,683-59,049 | ~3-30 GB | ~hours |
| **Bosons (nmax=2)** | 8-9 | 6,561-19,683 | ~400 MB-3 GB | ~10-60 min |
| **Spin-boson** | Varies | Depends | - | - |

### Memory Requirements

**Spin-1/2 systems:**
```julia
using Printf

function memory_estimate_spin_half(N)
    D = 2^N
    bytes = D^2 * 16  # ComplexF64 = 16 bytes
    GB = bytes / 1e9
    @printf("N=%d: D=%d, Memory=%.2f GB\n", N, D, GB)
end

for N in 10:16
    memory_estimate_spin_half(N)
end
```

**Output:**
```
N=10: D=1024, Memory=0.02 GB      ✅ Easy
N=11: D=2048, Memory=0.07 GB      ✅ Easy
N=12: D=4096, Memory=0.27 GB      ✅ OK
N=13: D=8192, Memory=1.07 GB      ⚠️ Slow
N=14: D=16384, Memory=4.29 GB     ⚠️ Very slow
N=15: D=32768, Memory=17.18 GB    ❌ Impractical
N=16: D=65536, Memory=68.72 GB    ❌ Impossible
```

### Speed vs Size

**Scaling behavior:**
```
N=8:   0.1 seconds
N=9:   0.5 seconds
N=10:  3 seconds
N=11:  20 seconds
N=12:  2 minutes
N=13:  15 minutes
N=14:  2 hours (estimate)
```

**Rule of thumb:** Each +1 in N multiplies time by ~8× for spin-1/2

### Recommendations

**For quick testing:**
```julia
N = 8  # Very fast, good for debugging
```

**For production runs:**
```julia
N = 10-12  # Sweet spot: reasonable time, good physics
```

**Maximum feasible:**
```julia
N = 13  # On powerful workstation
N = 14  # Only if you have time and memory
```

---

## ED Spectrum

### What It Does

Computes **all eigenvalues and eigenvectors** of the Hamiltonian.

**Output:**
- All energies: E₀ ≤ E₁ ≤ ... ≤ E_{D-1}
- All eigenstates: |ψ₀⟩, |ψ₁⟩, ..., |ψ_{D-1}⟩
- Ground state: |ψ₀⟩ with energy E₀
- Spectral gap: Δ = E₁ - E₀

### Basic Usage

**Minimal config:**
```julia
using TNCodebase
using JSON

config = Dict(
    "system" => Dict(
        "type" => "spin",
        "N" => 10
    ),
    "model" => Dict(
        "name" => "heisenberg",
        "params" => Dict(
            "Jx" => 1.0,
            "Jy" => 1.0,
            "Jz" => 1.0
        )
    ),
    "algorithm" => Dict(
        "type" => "ed_spectrum"
    )
)

# Run
run_simulation_from_config(config)
```

**Note:** No `"state"` section! ED computes eigenstates directly.

### Querying Results

```julia
# Find ED spectrum runs
results = query("sim", algorithm="ed_spectrum", N=10)
display_results(results)

# Get spectrum
run_dir = get_run_dirs(results)[1]
data = load(joinpath(run_dir, "results.jld2"))

eigenvalues = data["eigenvalues"]    # All energies
eigenvectors = data["eigenvectors"]  # All states (as columns)
```

### Analyzing Spectrum

```julia
using Plots

# Ground state properties
E0 = eigenvalues[1]
psi0 = eigenvectors[:, 1]

# Spectral gap
gap = eigenvalues[2] - eigenvalues[1]
println("Spectral gap: $gap")

# Plot full spectrum
scatter(1:length(eigenvalues), eigenvalues,
    xlabel="State index",
    ylabel="Energy",
    title="Full Spectrum (N=10)",
    markersize=2
)

# Density of states
histogram(eigenvalues, bins=50,
    xlabel="Energy",
    ylabel="Density of states",
    title="Energy Distribution"
)
```

### What You Can Do with the Spectrum

**1. Study excited states:**
```julia
# First excited state
E1 = eigenvalues[2]
psi1 = eigenvectors[:, 2]

# Energy gap to first excited state
gap = E1 - E0
```

**2. Calculate observables on all states:**
```julia
# See Observable Calculations section
# Can compute ⟨ψᵢ|O|ψᵢ⟩ for ALL states
```

**3. Thermal properties:**
```julia
# Partition function
β = 1.0  # Inverse temperature
Z = sum(exp.(-β * eigenvalues))

# Free energy
F = -log(Z) / β

# Entropy
E_avg = sum(eigenvalues .* exp.(-β * eigenvalues)) / Z
S = β * (E_avg - F)
```

**4. Level statistics:**
```julia
# Spacings
gaps = diff(eigenvalues)

# Nearest-neighbor spacing distribution
histogram(gaps, bins=30,
    xlabel="Energy spacing",
    ylabel="Count",
    title="Level Spacing Distribution"
)
```

---

## ED Time Evolution

### What It Does

Exact unitary evolution: |ψ(t)⟩ = exp(-iHt)|ψ(0)⟩

**Key difference from TDVP:**
- **ED:** Exact evolution (no Trotter error, no truncation)
- **TDVP:** Approximate (MPS truncation)

**Output:**
- State at each time step
- Saved to disk like TDVP for consistency

### Basic Usage

```julia
config = Dict(
    "system" => Dict(
        "type" => "spin",
        "N" => 10
    ),
    "model" => Dict(
        "name" => "heisenberg",
        "params" => Dict(
            "Jx" => 1.0,
            "Jy" => 1.0,
            "Jz" => 1.0
        )
    ),
    "state" => Dict(
        "type" => "prebuilt",
        "name" => "polarized",
        "params" => Dict(
            "spin_direction" => "Z",
            "eigenstate" => 1  # Spin up
        )
    ),
    "algorithm" => Dict(
        "type" => "ed_time_evolution",
        "dt" => 0.05,        # Time step
        "n_steps" => 200     # Total: 10 time units
    )
)

run_simulation_from_config(config)
```

### Time Evolution Parameters

**dt (time step):**
```julia
# Smaller dt = finer resolution, more data files
"dt" => 0.01   # Very fine (1000 steps for t=10)
"dt" => 0.05   # Good default (200 steps for t=10)
"dt" => 0.1    # Coarse (100 steps for t=10)
```

**n_steps:**
```julia
"n_steps" => 100   # Total time = dt × 100
"n_steps" => 200   # Total time = dt × 200
```

### How ED Time Evolution Works

**Two-stage process:**

**1. Preparation (expensive, done once):**
```julia
# Diagonalize H = V D V†
# Store eigenvalues E and eigenvectors V
```

**2. Evolution (cheap, per time step):**
```julia
# Express initial state in energy basis:
# |ψ(0)⟩ = Σᵢ cᵢ |Eᵢ⟩

# Evolve:
# |ψ(t)⟩ = Σᵢ cᵢ exp(-iEᵢt) |Eᵢ⟩
#       = V × [exp(-iE₀t), exp(-iE₁t), ...] × c

# Just phase factors! Very fast.
```

**Key insight:** Once H is diagonalized, getting |ψ(t)⟩ for any t is cheap!

### Querying Time Evolution Results

```julia
# Find time evolution runs
results = query("sim", algorithm="ed_time_evolution")

# Get run directory
run_dir = get_run_dirs(results)[1]

# Load state at specific time
using JLD2

# Time step 100 (t = dt × 100)
data = load(joinpath(run_dir, "step_100.jld2"))
psi_t = data["state"]
t = data["time"]

println("State at t=$t loaded")
```

### Calculating Time-Dependent Observables

```julia
# Create observable config
obs_config = Dict(
    "simulation" => config,  # Reference time evolution
    "observable" => Dict(
        "type" => "magnetization",
        "params" => Dict(
            "operator" => "Z",
            "site" => 1
        )
    ),
    "analysis" => Dict(
        "step_selection" => Dict("type" => "all")  # All time steps!
    )
)

run_observable_calculation_from_config(obs_config)

# Load magnetization vs time
obs_results = query("obs", 
    observable_type="magnetization",
    sim_algorithm="ed_time_evolution"
)

obs_dir = get_run_dirs(obs_results)[1]
obs_data = load(joinpath(obs_dir, "observables.jld2"))

times = obs_data["times"]
magnetization = obs_data["magnetization"]

# Plot dynamics
using Plots
plot(times, magnetization,
    xlabel="Time t",
    ylabel="⟨σᶻ₁⟩",
    title="Magnetization Decay",
    lw=2
)
```

---

## Observable Calculations

### On Eigenstates (ED Spectrum)

**Calculate observable on all eigenstates:**

```julia
# After running ED spectrum
sim_results = query("sim", algorithm="ed_spectrum", N=10)
sim_config = load_config(sim_results[1])

# Observable config
obs_config = Dict(
    "simulation" => sim_config,
    "observable" => Dict(
        "type" => "entanglement_entropy",
        "params" => Dict("bond" => 5)
    ),
    "analysis" => Dict(
        "state_selection" => Dict("type" => "all")  # All 1024 states!
    )
)

run_observable_calculation_from_config(obs_config)
```

**Result:** Entanglement entropy for every eigenstate!

**Plot entanglement vs energy:**
```julia
obs_results = query("obs", 
    observable_type="entanglement_entropy",
    sim_algorithm="ed_spectrum"
)

obs_data = load(joinpath(get_run_dirs(obs_results)[1], "observables.jld2"))
energies = obs_data["energies"]
entropies = obs_data["entanglement_entropy"]

scatter(energies, entropies,
    xlabel="Energy",
    ylabel="Entanglement Entropy",
    title="Entanglement-Energy Correlation",
    markersize=2
)
```

### On Ground State Only

```julia
obs_config = Dict(
    "simulation" => sim_config,
    "observable" => Dict("type" => "correlation_function", ...),
    "analysis" => Dict(
        "state_selection" => Dict(
            "type" => "specific",
            "indices" => [1]  # Ground state only
        )
    )
)
```

### On Time Evolution

**Already shown above** - use `"step_selection": {"type": "all"}`

### Available Observable Types

From your uploaded files, ED supports:

- **entanglement_entropy** - Von Neumann entropy at bond
- **correlation_function** - Two-point correlations
- **magnetization** - Single-site expectation values
- **energy** - Energy expectation (for verification)
- **custom** - Define your own operator

---

## Complete Workflows

### Workflow 1: Ground State Energy

```julia
using TNCodebase

# 1. Run ED spectrum
config = Dict(
    "system" => Dict("type" => "spin", "N" => 10),
    "model" => Dict("name" => "heisenberg", "params" => Dict(...)),
    "algorithm" => Dict("type" => "ed_spectrum")
)

run_simulation_from_config(config)

# 2. Query and extract
results = query("sim", algorithm="ed_spectrum", model_name="heisenberg")
E0 = results[1]["results_summary"]["ground_energy"]

println("Ground state energy: $E0")
```

### Workflow 2: Spectral Analysis

```julia
# 1. Run ED spectrum
run_simulation_from_config(config)

# 2. Load full spectrum
results = query("sim", algorithm="ed_spectrum")
data = load(joinpath(get_run_dirs(results)[1], "results.jld2"))

energies = data["eigenvalues"]
states = data["eigenvectors"]

# 3. Analyze
gap = energies[2] - energies[1]
println("Spectral gap: $gap")

# 4. Plot
using Plots
scatter(energies, markersize=2, xlabel="Index", ylabel="Energy")
```

### Workflow 3: Quantum Quench

```julia
# 1. Run time evolution from polarized state
config = Dict(
    "system" => Dict("type" => "spin", "N" => 10),
    "model" => Dict("name" => "heisenberg", ...),
    "state" => Dict("type" => "prebuilt", "name" => "polarized", ...),
    "algorithm" => Dict("type" => "ed_time_evolution", "dt" => 0.05, "n_steps" => 200)
)

run_simulation_from_config(config)

# 2. Calculate time-dependent magnetization
sim_results = query("sim", algorithm="ed_time_evolution")
sim_config = load_config(sim_results[1])

obs_config = Dict(
    "simulation" => sim_config,
    "observable" => Dict("type" => "magnetization", ...),
    "analysis" => Dict("step_selection" => Dict("type" => "all"))
)

run_observable_calculation_from_config(obs_config)

# 3. Plot dynamics
obs_results = query("obs", observable_type="magnetization")
obs_data = load(joinpath(get_run_dirs(obs_results)[1], "observables.jld2"))

plot(obs_data["times"], obs_data["magnetization"],
    xlabel="Time", ylabel="⟨σᶻ⟩", title="Quench Dynamics")
```

### Workflow 4: Benchmarking DMRG

```julia
# 1. Run both ED and DMRG
ed_config = Dict(
    "system" => Dict("type" => "spin", "N" => 10),
    "model" => Dict("name" => "heisenberg", ...),
    "algorithm" => Dict("type" => "ed_spectrum")
)

dmrg_config = Dict(
    "system" => Dict("type" => "spin", "N" => 10),
    "model" => Dict("name" => "heisenberg", ...),
    "state" => Dict("type" => "random", ...),
    "algorithm" => Dict("type" => "dmrg", ...)
)

run_simulation_from_config(ed_config)
run_simulation_from_config(dmrg_config)

# 2. Compare ground state energies
ed_results = query("sim", algorithm="ed_spectrum", N=10)
dmrg_results = query("sim", algorithm="dmrg", N=10)

ed_E0 = ed_results[1]["results_summary"]["ground_energy"]
dmrg_E0 = dmrg_results[1]["results_summary"]["ground_energy"]

error = abs(ed_E0 - dmrg_E0)
relative_error = error / abs(ed_E0)

println("ED ground energy:    $ed_E0")
println("DMRG ground energy:  $dmrg_E0")
println("Absolute error:      $error")
println("Relative error:      $(relative_error*100)%")
```

---

## Performance Tips

### 1. Use Sparse Matrices

ED automatically uses sparse matrices for large systems:
```julia
# Sparse used automatically for D > 20
# No user action needed
```

### 2. Choose Appropriate System Size

```julia
# For testing
N = 8  # Fast

# For production
N = 10-12  # Practical

# Maximum
N = 13  # Only if necessary
```

### 3. Don't Compute What You Don't Need

```julia
# If you only need ground state:
# Don't run full ed_spectrum
# Use specialized ground state solver (if available)

# If you only need low-energy states:
# Consider using Arpack's nev parameter
```

### 4. Memory Management

```julia
# For N=13-14, monitor memory:
using Sys

before = Sys.free_memory()
run_simulation_from_config(config)
after = Sys.free_memory()

println("Memory used: $((before - after) / 1e9) GB")
```

### 5. Time Step Choice for Evolution

```julia
# Don't over-resolve
# dt = 0.01 gives 1000 steps for t=10
# dt = 0.05 gives 200 steps for t=10

# Choose based on:
# - Fastest energy scale in H
# - Observable frequency of interest

# Rule of thumb: dt ~ 0.05 / max(|J|, |h|)
```

### 6. Parallel Computing

ED diagonalization is already parallelized (BLAS/LAPACK):
```julia
# Set number of threads
using LinearAlgebra
BLAS.set_num_threads(4)  # Use 4 cores
```

---

## Comparison with Other Methods

### ED vs DMRG

| Property | ED | DMRG |
|----------|----|----- |
| **System size** | N ≤ 12-14 | N ~ 100-1000 |
| **Accuracy** | Exact | Approximate (MPS) |
| **Ground state** | Yes (as ψ₀) | Yes (optimized) |
| **Excited states** | All states | Difficult |
| **Time** | O(D³) ~ hours | O(Nχ³) ~ minutes |
| **Memory** | O(D²) ~ GB | O(Nχ²) ~ MB |
| **Best for** | Small, exact | Large, ground state |

**Use ED for:**
- Small systems (N ≤ 12)
- Need exact results
- Want full spectrum
- Benchmark DMRG

**Use DMRG for:**
- Large systems (N > 14)
- Only need ground state
- 1D systems

### ED vs TDVP

| Property | ED Time Evolution | TDVP |
|----------|-------------------|------|
| **System size** | N ≤ 12 | N ~ 100-1000 |
| **Accuracy** | Exact | Approximate |
| **Time step** | Any (no Trotter) | Limited by Trotter |
| **Long time** | Exact | Accumulates error |
| **Best for** | Small, exact | Large, approximate |

**Use ED time evolution for:**
- Small systems
- Exact dynamics
- Benchmark TDVP
- No Trotter errors

**Use TDVP for:**
- Large systems
- Approximate dynamics OK

---

## Summary

### ED Strengths

✅ **Numerically exact** - Gold standard  
✅ **Full spectrum** - All eigenstates  
✅ **Exact evolution** - No approximations  
✅ **Excited states** - Natural output  
✅ **Benchmark quality** - Validate other methods

### ED Limitations

❌ **System size** - N ≤ 12-14 for spin-1/2  
❌ **Memory** - Exponential scaling  
❌ **Time** - Cubic scaling  
❌ **Dimensionality** - Only feasible for 1D

### When to Use ED

**Perfect for:**
- Small systems (N ≤ 12)
- Exact benchmarking
- Full spectrum analysis
- Excited state physics
- Exact time evolution

**Not suitable for:**
- Large systems (N > 14)
- 2D/3D systems
- Only need ground state of large system

### Quick Reference

```julia
# ED Spectrum
config = Dict(
    "system" => Dict("type" => "spin", "N" => 10),
    "model" => Dict("name" => "heisenberg", "params" => Dict(...)),
    "algorithm" => Dict("type" => "ed_spectrum")
)

# ED Time Evolution
config = Dict(
    "system" => Dict("type" => "spin", "N" => 10),
    "model" => Dict("name" => "heisenberg", "params" => Dict(...)),
    "state" => Dict("type" => "prebuilt", "name" => "polarized", ...),
    "algorithm" => Dict("type" => "ed_time_evolution", "dt" => 0.05, "n_steps" => 200)
)
```

---

**You're ready to use Exact Diagonalization in TNCodebase!** 🎉

**Next:** See example files for complete worked examples
- `heisenberg_ed_spectrum_README.md`
- `heisenberg_ed_time_evolution_README.md`
