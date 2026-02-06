# Heisenberg Model: ED Spectrum Example

## Overview

This example demonstrates **exact diagonalization (ED)** to compute the **complete eigenspectrum** of the Heisenberg model:
- ✅ Full diagonalization of Hamiltonian matrix
- ✅ All eigenvalues and eigenvectors computed
- ✅ Ground state, excited states, and spectral gap
- ✅ Foundation for observable calculations on eigenstates
- ✅ Automatic data saving with catalog indexing

**Complexity:** Beginner-friendly  
**Prerequisites:** Package installed and activated  
**System Size Limit:** N ≤ 12 (due to Hilbert space size 2^N)

---

## What This Example Does

### Physics

Computes the **full eigenspectrum** of the Heisenberg Model:

```
H = Jx Σᵢ σˣᵢσˣᵢ₊₁ + Jy Σᵢ σʸᵢσʸᵢ₊₁ + Jz Σᵢ σᶻᵢσᶻᵢ₊₁
  = 1.0 × Σᵢ σˣᵢσˣᵢ₊₁ + 1.0 × Σᵢ σʸᵢσʸᵢ₊₁ + 1.0 × Σᵢ σᶻᵢσᶻᵢ₊₁
```

**Physical interpretation:**
- **Jx = Jy = Jz = 1.0**: Isotropic antiferromagnetic Heisenberg (XXX model)
- **SU(2) symmetry**: Full rotational invariance in spin space
- **Ground state**: Singlet with antiferromagnetic correlations
- **Excited states**: Magnon excitations, multiplets

**Our parameters:**
- N = 10 sites (Hilbert space: 2^10 = 1024 states)
- Open boundary conditions
- Zero external field

### Algorithm

Uses **Exact Diagonalization (ED)**:

1. Build full Hamiltonian matrix (1024 × 1024)
2. Diagonalize to get all eigenvalues E₀, E₁, ..., E₁₀₂₃
3. Store all eigenvectors |ψ₀⟩, |ψ₁⟩, ..., |ψ₁₀₂₃⟩
4. Compute spectral properties

**What you get:**
- **Ground state energy E₀**: Lowest eigenvalue
- **Spectral gap Δ = E₁ - E₀**: Energy to first excited state
- **All eigenstates**: For calculating observables
- **Density of states**: Full spectrum structure

**Computational cost:**
- Memory: O(2^N × 2^N) ~ 1024² × 16 bytes ≈ 16 MB for N=10
- Time: O(2^3N) ~ few seconds for N=10
- Scales exponentially: N=12 feasible, N=14 slow, N=16+ impractical

---

## Files

```
heisenberg/
├── ed_spectrum_README.md       # This file
├── ed_spectrum_config.json     # All simulation parameters
└── ed_spectrum_run.jl          # Main script
```

---

## Usage

### Quick Start

```bash
# Navigate to this directory
cd examples/00_quickstart/heisenberg

# Run the example
julia ed_spectrum_run.jl
```

The script will:
1. Load configuration from `ed_spectrum_config.json`
2. Build the Heisenberg Hamiltonian (1024 × 1024 matrix)
3. Diagonalize to get all 1024 eigenstates
4. Save eigenvalues and eigenvectors to `data/ed_spectrum/`

### Expected Output

```
======================================================================
Heisenberg Model: ED Spectrum Calculation
======================================================================

📋 Configuration loaded from: ed_spectrum_config.json

   System: spin chain
   N sites: 10
   Model: heisenberg
   Hilbert space dimension: 2^10 = 1024

🚀 Starting exact diagonalization...

======================================================================
Starting ED Simulation: ED_SPECTRUM
======================================================================

[1/5] Checking for existing runs...
  No completed run found. Proceeding...

[2/5] Setting up database...
✓ Setup complete: data/ed_spectrum/20260206_120534_a3f8b912
  ✓ Run ID: 20260206_120534_a3f8b912

[3/5] Building Hamiltonian...
  ✓ Hamiltonian: 1024 × 1024
  ✓ Sparsity: 1.07%

[4/5] Running simulation...
======================================================================
  Solving full spectrum (D = 1024)...
  ✓ Diagonalization complete
    Ground state energy: -4.258
    Spectral gap: 0.634
    States computed: 1024

  Saving results...
  ✓ Results saved to results.jld2
======================================================================

[5/5] Finalizing...
  ✓ Run finalized with status: completed
  ✓ Run marked as completed
  ✓ Appended to catalog: 20260206_120534_a3f8b912

✅ ED Spectrum calculation complete!
```

---

## Understanding the Configuration

The `ed_spectrum_config.json` file has **NO STATE SECTION** (unlike DMRG):

### 1. System
```json
"system": {
  "type": "spin",
  "N": 10
}
```
- Defines 10 spin-1/2 sites
- Hilbert space dimension: 2^10 = 1024

### 2. Model
```json
"model": {
  "name": "heisenberg",
  "params": {
    "N": 10,
    "Jx": 1.0,
    "Jy": 1.0,
    "Jz": 1.0,
    "dtype": "ComplexF64"
  }
}
```
- Isotropic Heisenberg
- ComplexF64 required for σʸ operators

### 3. Algorithm (Simple!)
```json
"algorithm": {
  "type": "ed_spectrum"
}
```
- No parameters needed - just diagonalize!
- Computes ALL eigenstates automatically

**Note:** No initial state needed! ED computes eigenstates directly.

---

## Modifying the Example

### System Size Variations

**Smaller (faster):**
```json
"N": 8
```
- Hilbert space: 2^8 = 256
- Very fast (~0.1 seconds)
- Good for testing

**Larger (still feasible):**
```json
"N": 12
```
- Hilbert space: 2^12 = 4096
- ~10-30 seconds
- Maximum practical size for full spectrum

**Too large (don't try):**
```json
"N": 14  // 16384 states - slow
"N": 16  // 65536 states - very slow
"N": 20  // 1048576 states - infeasible!
```

### Model Variations

**1. XXZ model (anisotropic):**
```json
"Jz": 2.0
```
- Breaks SU(2) to U(1) symmetry
- Larger spectral gap

**2. Transverse field Ising:**
```json
"name": "transverse_field_ising",
"params": {
  "Jx": 1.0,
  "hz": 0.5
}
```
- Simpler model
- Can use Float64 instead of ComplexF64

**3. Add magnetic field:**
```json
"hz": 0.3
```
- Breaks SU(2) symmetry
- Shifts energy levels

---

## Working with Results

### 1. Query Results

```julia
using TNCodebase

# Find all ED spectrum runs
results = query("sim", algorithm="ed_spectrum")
display_results(results)

# Get the run ID
ids = get_run_ids(results)
run_id = ids[1]
```

### 2. Load Eigenspectrum

```julia
using JLD2

# Load from query results
dir = get_run_dirs(results)[1]
data = load(joinpath(dir, "results.jld2"))

# Extract eigenvalues and eigenvectors
eigenvalues = data["eigenvalues"]    # Vector of 1024 energies
eigenvectors = data["eigenvectors"]  # 1024 × 1024 matrix
```

### 3. Analyze Spectrum

```julia
# Ground state properties
E_ground = eigenvalues[1]
spectral_gap = eigenvalues[2] - eigenvalues[1]

println("Ground state energy: $E_ground")
println("Spectral gap: $spectral_gap")

# Plot spectrum
using Plots
scatter(1:length(eigenvalues), eigenvalues,
    xlabel="State index",
    ylabel="Energy",
    title="Heisenberg Spectrum (N=10)",
    markersize=2
)
```

### 4. Density of States

```julia
using StatsBase

# Histogram of eigenvalues
h = fit(Histogram, eigenvalues, nbins=50)

plot(h.edges[1][1:end-1], h.weights,
    xlabel="Energy",
    ylabel="Density of states",
    title="Heisenberg DOS (N=10)",
    seriestype=:steppost
)
```

---

## Observable Calculations

The real power of ED spectrum is calculating observables on ALL eigenstates!

### Example: Entanglement Entropy on All States

```julia
# After running ED spectrum, calculate entanglement
obs_config = Dict(
    "simulation" => config,  # Reference the ED run
    "observable" => Dict(
        "type" => "entanglement_entropy",
        "params" => Dict("bond" => 5)
    ),
    "analysis" => Dict(
        "state_selection" => Dict("type" => "all")
    )
)

run_observable_calculation_from_config(obs_config)
```

This calculates entanglement entropy for **all 1024 eigenstates**!

### Query Observable Results

```julia
# Find entanglement results
obs_results = query("obs",
    observable_type="entanglement_entropy",
    sim_algorithm="ed_spectrum"
)

display_results(obs_results)

# Load and plot
obs_dir = get_run_dirs(obs_results)[1]
obs_data = load(joinpath(obs_dir, "observables.jld2"))

# Plot entanglement vs energy
scatter(eigenvalues, obs_data["entanglement_entropy"],
    xlabel="Energy",
    ylabel="Entanglement Entropy S",
    title="Entanglement-Energy Correlation"
)
```

---

## Physics Notes

### Ground State Properties

For **N = 10 Heisenberg chain**:
- Ground state energy: E₀ ≈ -4.26
- Ground state is a **singlet** (total spin S=0)
- Antiferromagnetic correlations

### Spectral Structure

**Low-energy states:**
- Magnon excitations (S=1 triplets)
- Two-magnon states (S=0, 1, 2)
- Form multiplets due to SU(2) symmetry

**High-energy states:**
- Multi-magnon states
- Ferromagnetic state at top

### Spectral Gap

The spectral gap Δ = E₁ - E₀:
- For N=10: Δ ≈ 0.63
- Larger for smaller systems
- Vanishes as N→∞ (gapless spin chain)

---

## ED Spectrum vs DMRG

| Property | ED Spectrum | DMRG |
|----------|-------------|------|
| **System size** | N ≤ 12 | N ~ 100-1000 |
| **States computed** | ALL (2^N) | One (ground state) |
| **Excited states** | Yes, all | No |
| **Memory** | O(4^N) | O(Nχ²) |
| **Time** | O(8^N) | O(Nχ³) sweeps |
| **Observables** | On all states | On ground state |
| **Best for** | Small, full spectrum | Large, ground state |

**When to use ED Spectrum:**
- Small systems (N ≤ 12)
- Need excited states
- Want full spectrum analysis
- Calculate observables on many states

**When to use DMRG:**
- Large systems (N > 12)
- Only need ground state
- Want low-energy properties

---

## Troubleshooting

### Issue: Out of memory

**Error:** `OutOfMemoryError` during diagonalization

**Cause:** Hilbert space too large (N > 12)

**Solutions:**
1. Reduce N to 10 or 11
2. Use sparse diagonalization (only low-energy states)
3. Switch to DMRG for large systems

### Issue: Slow diagonalization

**Symptom:** Takes minutes for N=12

**This is normal!** Full diagonalization of 4096×4096 matrix is expensive.

**Solutions:**
- Be patient (it's still exact)
- Use smaller N for testing
- Consider iterative methods for low-energy only

---

## Next Steps

After computing the spectrum:

1. **Calculate observables:**
   - Entanglement entropy on all states
   - Correlation functions vs energy
   - Magnetization in excited states

2. **Compare with DMRG:**
   - Run DMRG on same parameters
   - Verify ground state energy matches
   - See DMRG limitations for excited states

3. **Try time evolution:**
   - Start from an eigenstate
   - Evolve forward in time
   - See quantum dynamics (next example!)

---

## See Also

**Related Examples:**
- `heisenberg_ed_time_evolution_README.md` - Time evolution with ED
- `heisenberg_dmrg_README.md` - Ground state with DMRG
- `examples/observables/` - Observable calculations

**Documentation:**
- `docs/exact_diagonalization.md` - ED theory and methods
- `docs/query_system.md` - How to query results

---

## Summary

This example demonstrates:

✅ **Full eigenspectrum** - All 1024 eigenstates for N=10  
✅ **Ground state energy** - Exact result  
✅ **Spectral gap** - Energy to first excited state  
✅ **Observable foundation** - Calculate on any eigenstate  
✅ **Professional output** - Organized data, catalog indexing

**You've successfully computed the Heisenberg eigenspectrum!**

**Next:** Try `ed_time_evolution_run.jl` to see quantum dynamics! →
