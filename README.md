# TNCodebase: Comprehensive Framework for Quantum Many-Body Simulations

*Combining Tensor Network methods (DMRG, TDVP) and Exact Diagonalization for complementary approaches to quantum many-body physics*

A comprehensive and user-friendly Julia package for simulating quantum many-body systems using both tensor network methods and exact diagonalization, where users interact with the engine through a single JSON config file. Implements state-of-the-art algorithms with an emphasis on extensibility, performance, and reproducibility.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Julia](https://img.shields.io/badge/Julia-1.9+-blue.svg)](https://julialang.org/)
[![Methods](https://img.shields.io/badge/Methods-TN%20%2B%20ED-green.svg)](https://github.com/yourusername/TNCodebase)

---

## Overview

TNCodebase provides a complete framework for quantum many-body simulations combining two complementary approaches:

- **Tensor Network methods** (DMRG, TDVP): Approximate but scalable to N~100-1000 sites
- **Exact Diagonalization** (ED): Numerically exact but limited to N≤12-14 sites

This dual approach enables:
- ✅ **Benchmarking**: Validate TN results against exact ED for small systems
- ✅ **Method selection**: Choose optimal algorithm based on system size and accuracy needs
- ✅ **Unified workflow**: Same config-driven interface for both approaches
- ✅ **Complete toolkit**: From exact small-system physics to large-scale approximate dynamics

### Core Features

- **Flexible algorithm implementations**: DMRG for ground states, TDVP for time evolution, ED for exact solutions
- **Config-driven workflow**: JSON-based specification of models, states, and algorithms
- **Automatic data management**: Hash-based indexing, catalog system, and organized storage
- **Powerful query system**: Fast JSONL-based queries with HTML builder interface
- **Extensible architecture**: Easy addition of new Hamiltonians, observables, and algorithms

The package implements a fully config-driven workflow for quantum simulations. Users specify all simulation parameters (system, Hamiltonian, state, algorithm) via a single JSON file. The engine automatically saves all results with complete metadata using a hash-based indexing system: each unique configuration generates an identifying hash for O(1) lookup, preventing redundant calculations and ensuring reproducibility.

A decoupled observable calculation engine computes physical observables on saved states (MPS or eigenvectors) through separate JSON configs, eliminating the need to re-run expensive simulations. All data is automatically organized, indexed, and linked via the catalog system, creating complete provenance tracking from input configuration to final results.

This architecture is designed for large-scale parameter studies, algorithm benchmarking, and collaborative research where reproducibility and efficient data management are critical.

---

## Key Features

### 🔬 **Algorithms**

**Tensor Network Methods** (Large Systems, N > 14):
- **DMRG**: Two-site algorithm with Lanczos eigensolver for ground state search
- **TDVP**: Two-site + one-site algorithm with Krylov exponential integrator for time evolution
- **Optimized tensor operations**: Canonical form management, SVD truncation, environment caching

**Exact Diagonalization** (Small Systems, N ≤ 12-14):
- **ED Spectrum**: Full diagonalization for all eigenstates and eigenvalues
- **ED Time Evolution**: Exact unitary evolution via eigendecomposition
- **Benchmarking**: Gold-standard results for validating approximate methods

### 🎯 **Physical Systems**
- **Spin chains**: Arbitrary spin-S with custom operators
- **Long-range interactions**: Exponential and power-law couplings via finite state machines (TN) or exact implementation (ED)
- **Spin-boson models**: Coupled spin-boson systems for light-matter interactions
- **Custom Hamiltonians**: Flexible channel-based construction (TN) or term-based assembly (ED)

### 📊 **Observables**
- Single-site and two-site expectation values
- Correlation functions (connected and raw)
- Entanglement entropy and spectrum
- Energy expectation and variance
- Works with both MPS states (DMRG/TDVP) and exact eigenstates (ED)

### 🗄️ **Data Management & Query System**
- Hash-based simulation indexing for O(1) lookup
- Fast JSONL catalog for millisecond queries across thousands of runs
- HTML query builder for visual exploration
- Automatic catalog updates on simulation completion
- Filter by algorithm, model, parameters, system size, results
- Cross-reference simulations and observables
- Separate observable calculation and storage

---

## Method Comparison: When to Use What

| Criterion | Exact Diagonalization (ED) | Tensor Networks (DMRG/TDVP) |
|-----------|---------------------------|----------------------------|
| **System Size** | N ≤ 12-14 (spin-1/2) | N ~ 100-1000 |
| **Accuracy** | Exact (machine precision) | Approximate (controlled by χ) |
| **Ground State** | Yes (+ all excited states) | Yes (ground state only) |
| **Excited States** | All eigenstates naturally | Difficult, specialized methods |
| **Time Evolution** | Yes (exact, no Trotter) | Yes (approximate, TDVP) |
| **Memory** | O(2^N) ~ GB for N=14 | O(Nχ²) ~ MB |
| **Speed** | O(2^(3N)) ~ hours | O(Nχ³) ~ minutes |
| **Full Spectrum** | Yes | No |
| **Best For** | Benchmarking, small systems, spectroscopy | Large systems, 1D/quasi-1D dynamics |

### When to Use ED:
✅ **Benchmarking**: Validate DMRG/TDVP accuracy on small systems  
✅ **Small systems**: N ≤ 12 for detailed analysis  
✅ **Full spectrum**: Need all eigenstates and eigenvalues  
✅ **Excited states**: Study spectral properties, gaps, level statistics  
✅ **Exact dynamics**: Time evolution without Trotter or MPS truncation errors

### When to Use Tensor Networks:
✅ **Large systems**: N > 14 (ED becomes impractical)  
✅ **Ground state only**: Don't need full spectrum  
✅ **1D/quasi-1D**: Where TN methods excel  
✅ **Entanglement area law**: MPS efficiently represents these states  
✅ **Long-time dynamics**: TDVP for extended time evolution

### Recommended Workflow:
1. **Development** (N=8-10): Use ED for exact validation and debugging
2. **Benchmarking** (N=10-12): Compare ED vs DMRG/TDVP accuracy
3. **Production** (N>14): Use DMRG/TDVP for large-scale physics
4. **Analysis**: Calculate observables on both ED eigenstates and MPS

---

## Quick Start

### Installation

```julia
# Clone the repository
git clone https://github.com/yourusername/TNCodebase.git
cd TNCodebase

# Add to Julia
using Pkg
Pkg.activate(".")
Pkg.instantiate()
```

### Basic Usage: Tensor Networks

```julia
using JSON
using TNCodebase

# 1. Define simulation via config file
config = JSON.parsefile("examples/00_quickstart_dmrg/config.json")

# 2. Run simulation (auto-saves results)
state, run_id, run_dir = run_simulation_from_config(config)

# 3. Query and load results
results = query("sim", algorithm="dmrg", model_name="heisenberg")
display_results(results)

# 4. Load specific run
mps, extra_data = load_mps_sweep(results[1]["run_dir"], 50)
```

### Basic Usage: Exact Diagonalization

```julia
using TNCodebase

# 1. ED spectrum calculation
ed_config = Dict(
    "system" => Dict("type" => "spin", "N" => 10),
    "model" => Dict("name" => "heisenberg", "params" => Dict(...)),
    "algorithm" => Dict("type" => "ed_spectrum")
)

run_simulation_from_config(ed_config)

# 2. Query results
results = query("sim", algorithm="ed_spectrum", N=10)
display_results(results)

# 3. Load eigenvalues and eigenvectors
data = load(joinpath(results[1]["run_dir"], "results.jld2"))
eigenvalues = data["eigenvalues"]
eigenvectors = data["eigenvectors"]
```

### Query System

```julia
# Visual query builder (opens in browser)
build_query("sim")

# Programmatic queries
results = query("sim",
    algorithm="dmrg",
    model_name="heisenberg",
    N_gte=20,              # N >= 20
    algo_chi_max_gte=100   # chi_max >= 100
)

# Display results
display_results_compact(results)  # Table view
display_results(results)          # Detailed view

# Extract information
ids = get_run_ids(results)
dirs = get_run_dirs(results)
config = load_config(results[1])
```

---

## AI Simulation Chatbot

TNCodebase includes a natural-language chatbot that lets you set up and run Exact Diagonalization simulations through a conversational interface — no Julia or JSON knowledge required.

**Architecture:**
```
Browser (port 8000)
  ↕ HTTP
FastAPI server (chatbot/app.py)
  ↕ AWS Bedrock API
Claude 3 Haiku  ←  builds simulation configs from natural language
  ↕ HTTP
Julia pipeline server (port 8080)
  ↕ in-process
TNCodebase.run_simulation_from_config(...)
```

**Supported via chatbot:**
- Models: `transverse_field_ising`, `heisenberg`, `long_range_ising`
- Algorithms: `ed_spectrum` (energy levels), `ed_time_evolution` (dynamics)
- System sizes: N ≤ 14 (ED constraint — for larger systems use the Julia API directly)

---

### Chatbot Setup

#### 1. AWS CLI

Install the AWS CLI for your platform:

```bash
# macOS
brew install awscli

# Linux
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip && sudo ./aws/install

# Windows — download and run the MSI installer from:
# https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html
```

Verify installation:
```bash
aws --version
```

#### 2. Enable Claude 3 Haiku in AWS Bedrock

1. Sign in to the [AWS Console](https://console.aws.amazon.com)
2. Navigate to **Amazon Bedrock → Model access → Manage model access**
3. Enable **Anthropic → Claude 3 Haiku**
4. Your IAM user/role needs the `bedrock:InvokeModel` permission

The chatbot uses model ID `anthropic.claude-3-haiku-20240307-v1:0` in region `us-east-1`.

#### 3. Configure AWS Credentials

**Option A — IAM access keys:**
```bash
aws configure
# Enter your AWS Access Key ID, Secret Access Key, default region (us-east-1), and output format
```

**Option B — SSO (recommended for organizations):**
```bash
aws configure sso
# Follow the prompts to set up your SSO profile, then:
aws sso login --profile <your-profile-name>

# Tell the chatbot which profile to use:
export AWS_PROFILE=<your-profile-name>
```

#### 4. Python Dependencies

```bash
pip install -r chatbot/requirements.txt
```

---

### Running the Chatbot

The Julia pipeline server **must be started first** — the chatbot forwards confirmed simulation configs to it.

**Terminal 1 — Julia pipeline server:**
```bash
julia --project=. start_server.jl
# Starts HTTP server at http://127.0.0.1:8080
# Auto-opens the config builder GUI in your browser
```

**Terminal 2 — Chatbot server:**
```bash
uvicorn chatbot.app:app --host 127.0.0.1 --port 8000 --reload
```

Open **http://127.0.0.1:8000** in your browser.

---

### How It Works

1. **Describe your simulation** in plain English — e.g. *"I want the ground state energy levels of a 10-site Heisenberg chain"*
2. **Claude 3 Haiku** (via AWS Bedrock) asks any clarifying questions and assembles a complete JSON simulation config
3. **Review the config** in the right panel — you can edit the JSON manually before running
4. **Click Confirm & Run** — the config is sent to the Julia pipeline server and executed
5. **Results are interpreted** — Claude reads the output and explains what the results mean in the context of your physics question

The conversation history is stored in memory and your `session_id` is saved in browser `localStorage`, so reloading the page resumes where you left off.

---

## Example: Ground State Energy Convergence (DMRG)

```julia
using JSON, Plots
using TNCodebase

# DMRG simulation config
config = Dict(
    "system" => Dict("type" => "spin", "N" => 50),
    "model" => Dict(
        "name" => "transverse_field_ising",
        "params" => Dict("N" => 50, "J" => -1.0, "h" => 0.5,
                        "coupling_dir" => "Z", "field_dir" => "X")
    ),
    "state" => Dict("type" => "random", "params" => Dict("bond_dim" => 10)),
    "algorithm" => Dict(
        "type" => "dmrg",
        "solver" => Dict("type" => "lanczos", "krylov_dim" => 6, "max_iter" => 20),
        "options" => Dict("chi_max" => 100, "cutoff" => 1e-10, "local_dim" => 2),
        "run" => Dict("n_sweeps" => 50)
    )
)

# Run simulation
state, run_id, run_dir = run_simulation_from_config(config, base_dir="data")

# Load and plot energy convergence
metadata = JSON.parsefile(joinpath(run_dir, "metadata.json"))
energies = [sweep["energy"] for sweep in metadata["sweep_data"]]

plot(1:length(energies), energies,
     xlabel="Sweep", ylabel="Energy", 
     title="DMRG Ground State Convergence",
     legend=false, linewidth=2)
```

**Output**: Demonstrates exponential convergence to ground state energy.

---

## Example: Time Evolution with TDVP

```julia
# Start from polarized state
config = Dict(
    "system" => Dict("type" => "spin", "N" => 40),
    "model" => Dict(
        "name" => "transverse_field_ising",
        "params" => Dict("N" => 40, "J" => -1.0, "h" => 2.0,
                        "coupling_dir" => "Z", "field_dir" => "X")
    ),
    "state" => Dict(
        "type" => "prebuilt", "name" => "polarized",
        "params" => Dict("spin_direction" => "Z", "eigenstate" => 2)
    ),
    "algorithm" => Dict(
        "type" => "tdvp",
        "solver" => Dict("type" => "krylov_exponential", 
                        "krylov_dim" => 20, "tol" => 1e-10, "evol_type" => "real"),
        "options" => Dict("dt" => 0.01, "chi_max" => 100, 
                         "cutoff" => 1e-10, "local_dim" => 2),
        "run" => Dict("n_sweeps" => 500)
    )
)

# Run time evolution
state, run_id, run_dir = run_simulation_from_config(config, base_dir="data")

# Query results
results = query("sim", algorithm="tdvp", N=40)
display_results(results)
```

**Output**: Shows time evolution dynamics after quantum quench.

---

## Example: Exact Benchmarking with ED

```julia
using TNCodebase
using Plots

# Small system - use ED for exact results
ed_config = Dict(
    "system" => Dict("type" => "spin", "N" => 10),
    "model" => Dict(
        "name" => "transverse_field_ising",
        "params" => Dict("J" => -1.0, "h" => 0.5,
                        "coupling_dir" => "Z", "field_dir" => "X")
    ),
    "algorithm" => Dict("type" => "ed_spectrum")
)

# Run ED (gets ALL eigenstates)
run_simulation_from_config(ed_config, base_dir="data")

# Also run DMRG for comparison
dmrg_config = Dict(
    "system" => Dict("type" => "spin", "N" => 10),
    "model" => Dict(
        "name" => "transverse_field_ising",
        "params" => Dict("J" => -1.0, "h" => 0.5,
                        "coupling_dir" => "Z", "field_dir" => "X")
    ),
    "state" => Dict("type" => "random", "params" => Dict("bond_dim" => 10)),
    "algorithm" => Dict(
        "type" => "dmrg",
        "solver" => Dict("type" => "lanczos", "krylov_dim" => 4, "max_iter" => 14),
        "options" => Dict("chi_max" => 100, "cutoff" => 1e-10, "local_dim" => 2),
        "run" => Dict("n_sweeps" => 50)
    )
)

run_simulation_from_config(dmrg_config, base_dir="data")

# Compare ground state energies using query system
ed_results = query("sim", algorithm="ed_spectrum", N=10, 
                   model_name="transverse_field_ising")
dmrg_results = query("sim", algorithm="dmrg", N=10, 
                     model_name="transverse_field_ising")

ed_E0 = ed_results[1]["results_summary"]["ground_energy"]
dmrg_E0 = dmrg_results[1]["results_summary"]["ground_energy"]

error = abs(ed_E0 - dmrg_E0)
relative_error = error / abs(ed_E0)

println("═════════════════════════════════════")
println("     Benchmarking DMRG vs ED")
println("═════════════════════════════════════")
println("ED ground energy:    $ed_E0 (exact)")
println("DMRG ground energy:  $dmrg_E0 (χ=100)")
println("Absolute error:      $error")
println("Relative error:      $(relative_error*100)%")
println("═════════════════════════════════════")
```

**Output**: Demonstrates DMRG accuracy by comparison with exact ED results.

---

## Example: Full Spectrum Analysis with ED

```julia
using TNCodebase
using Plots

# Run ED spectrum
config = Dict(
    "system" => Dict("type" => "spin", "N" => 10),
    "model" => Dict(
        "name" => "heisenberg",
        "params" => Dict("Jx" => 1.0, "Jy" => 1.0, "Jz" => 1.0,
                        "hx" => 0.0, "hy" => 0.0, "hz" => 0.0)
    ),
    "algorithm" => Dict("type" => "ed_spectrum")
)

run_simulation_from_config(config)

# Load full spectrum
results = query("sim", algorithm="ed_spectrum", model_name="heisenberg", N=10)
data = load(joinpath(results[1]["run_dir"], "results.jld2"))

eigenvalues = data["eigenvalues"]    # All 1024 energies
eigenvectors = data["eigenvectors"]  # All 1024 states

# Analyze spectrum
ground_energy = eigenvalues[1]
spectral_gap = eigenvalues[2] - eigenvalues[1]

println("Ground state energy: $ground_energy")
println("Spectral gap: $spectral_gap")

# Plot full spectrum
scatter(1:length(eigenvalues), eigenvalues,
    xlabel="State index",
    ylabel="Energy",
    title="Full Energy Spectrum (Heisenberg N=10)",
    markersize=2,
    legend=false
)

# Density of states
histogram(eigenvalues, bins=50,
    xlabel="Energy",
    ylabel="Density of states",
    title="Energy Distribution"
)
```

**Output**: Complete eigenspectrum showing all energy levels and gaps.

---

## Project Structure

```
TNCodebase/
├── src/
│   ├── Core/                   # Types, operators, finite state machines
│   ├── TensorOps/             # Canonicalization, SVD, environments
│   ├── Algorithms/            # DMRG, TDVP, solvers
│   ├── ED/                    # Exact Diagonalization
│   │   ├── ed_basis.jl        #   Hilbert space construction & embedding
│   │   ├── ed_operators.jl    #   Primitive operators (σ, b, b†)
│   │   ├── ed_solver.jl       #   Eigensolvers & time evolution
│   │   ├── ed_hamiltonian.jl  #   Hamiltonian assembly
│   │   ├── ed_models.jl       #   Model builders
│   │   ├── ed_terms.jl        #   Interaction term types
│   │   ├── ed_states.jl       #   Initial state preparation
│   │   └── ed_observables.jl  #   Observable calculations
│   ├── Builders/              # Config-driven construction
│   ├── Database/              # Data management & catalog system
│   │   ├── database_catalog.jl           # Simulation catalog
│   │   ├── database_observables_catalog.jl # Observable catalog
│   │   ├── query_catalog.jl              # Query functions
│   │   └── query_builder.jl              # HTML query builder
│   ├── Runners/               # Simulation execution
│   └── Analysis/              # Observable calculations
│
├── examples/                   # Complete working examples
│   ├── 00_quickstart_dmrg/    # DMRG ground state search
│   ├── 01_quickstart_tdvp/    # TDVP time evolution
│   ├── 02_ed_spectrum/        # ED full spectrum
│   ├── 03_ed_time_evolution/  # ED time dynamics
│   ├── models/                # Model building examples
│   │   ├── prebuilt_models/   # Template-based models + reference
│   │   └── custom_models/     # Channel-based construction
│   └── states/                # State preparation examples
│       ├── prebuilt_states/   # Template-based states + reference
│       └── custom_states/     # Site-by-site specification
│
├── docs/                       # Documentation
│   ├── model_building.md
│   ├── state_building.md
│   ├── QUERY_SYSTEM_GUIDE.md            # Query API reference
│   ├── CATALOG_SYSTEM_ARCHITECTURE.md   # Catalog internals
│   ├── CATALOG_QUERY_INTEGRATION.md     # Complete workflows
│   ├── ED_USER_GUIDE.md                 # Using ED
│   └── ED_ARCHITECTURE_GUIDE.md         # ED internals
│
├── chatbot/                    # AI simulation chatbot
│   ├── app.py                 # FastAPI server (AWS Bedrock + Julia pipeline proxy)
│   ├── requirements.txt       # Python dependencies
│   └── static/
│       └── index.html         # Two-column chat + config review UI
│
├── pipeline_server.jl          # HTTP pipeline automation server (REST API)
├── start_server.jl             # Server startup (loads TNCodebase → starts HTTP server)
│
└── test/                       # Unit tests
```

---

## Configuration System

TNCodebase uses JSON configuration files to specify simulations, enabling:
- **Reproducibility**: Complete simulation specification in one file
- **Parameter sweeps**: Easy modification for systematic studies
- **Data organization**: Automatic indexing by configuration hash
- **Method agnostic**: Same config structure works for TN and ED (just change algorithm type)

### Tensor Network Config Example

```json
{
  "system": {
    "type": "spin",
    "N": 50,
    "S": 0.5
  },
  "model": {
    "name": "transverse_field_ising",
    "params": {
      "J": -1.0,
      "h": 0.5,
      "coupling_dir": "Z",
      "field_dir": "X"
    }
  },
  "state": {
    "type": "prebuilt",
    "name": "neel"
  },
  "algorithm": {
    "type": "dmrg",
    "solver": {"type": "lanczos", "krylov_dim": 4, "max_iter": 14},
    "options": {"chi_max": 100, "cutoff": 1e-8, "local_dim": 2},
    "run": {"n_sweeps": 50}
  }
}
```

### Exact Diagonalization Config Example

```json
{
  "system": {
    "type": "spin",
    "N": 10,
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
  "algorithm": {
    "type": "ed_spectrum"
  }
}
```

**Note**: No `"state"` section needed for `ed_spectrum` - it computes eigenstates directly!

For ED time evolution:
```json
{
  "system": {"type": "spin", "N": 10},
  "model": {"name": "heisenberg", "params": {...}},
  "state": {
    "type": "prebuilt",
    "name": "polarized",
    "params": {"spin_direction": "Z", "eigenstate": 1}
  },
  "algorithm": {
    "type": "ed_time_evolution",
    "dt": 0.05,
    "n_steps": 200
  }
}
```

---

## Data Management & Query System

TNCodebase includes a powerful catalog and query system for organizing simulations:

```julia
# Visual query builder (opens in browser)
build_query("sim")          # For simulations
build_query("obs")          # For observables

# Programmatic queries with flexible filters
results = query("sim", 
    algorithm="dmrg",
    model_name="heisenberg",
    N_gte=20,              # N >= 20
    algo_chi_max_gte=100   # chi_max >= 100
)

# Query ED runs
ed_results = query("sim",
    algorithm="ed_spectrum",
    N=10,
    model_name="transverse_field_ising"
)

# Query observables
obs_results = query("obs",
    observable_type="entanglement_entropy",
    sim_algorithm="dmrg"
)

# Display results
display_results_compact(results)  # Table view
display_results(results)          # Detailed view

# Extract information
ids = get_run_ids(results)
dirs = get_run_dirs(results)
config = load_config(results[1])

# Catalog statistics
catalog_summary("sim")  # Summary of all simulations
catalog_summary("obs")  # Summary of all observables
```

### Query Features:
- ✅ **Fast JSONL-based catalog** - Millisecond queries across thousands of runs
- ✅ **Flexible filtering** - By algorithm, model, parameters, system size, results
- ✅ **Comparison operators** - `_gt`, `_gte`, `_lt`, `_lte` for numeric fields
- ✅ **HTML query builder** - Visual interface for exploration
- ✅ **Automatic updates** - Catalog updated on simulation completion
- ✅ **Cross-referencing** - Link observables to parent simulations
- ✅ **Type auto-detection** - Functions work with both simulation and observable results

### Documentation:
- `docs/QUERY_SYSTEM_GUIDE.md` - Complete query API and examples
- `docs/CATALOG_SYSTEM_ARCHITECTURE.md` - How catalogs are built
- `docs/CATALOG_QUERY_INTEGRATION.md` - End-to-end workflows

---

## Implemented Models

### Pre-built Models
- **Transverse Field Ising Model**: `H = J Σᵢ σᶻᵢσᶻᵢ₊₁ + h Σᵢ σˣᵢ`
- **Heisenberg Chain**: `H = Jₓ Σᵢ σˣᵢσˣᵢ₊₁ + Jᵧ Σᵢ σʸᵢσʸᵢ₊₁ + Jᵧ Σᵢ σᶻᵢσᶻᵢ₊₁`
- **Long-Range Ising**: `H = J Σᵢ<ⱼ σᶻᵢσᶻⱼ/|i-j|^α + h Σᵢ σˣᵢ`
- **Spin-Boson Model**: Coupled spin chain + bosonic mode

**Note:** All models work with both Tensor Network and Exact Diagonalization methods:
- **TN methods**: Use finite state machines (FSM) for efficient MPO construction
- **ED methods**: Direct Hamiltonian matrix construction (no FSM needed, exact power-law for long-range)

The same JSON config works for both approaches - just change the algorithm type!

### Custom Models
Define models via:
- **TN**: Channel specifications (finite-range, exponential decay, power-law via sum-of-exponentials)
- **ED**: Term specifications (nearest-neighbor, power-law exact, fields)

Both support single-site fields and multi-site interactions.

---

## Performance Highlights

### Tensor Network Methods:
- **Efficient tensor contractions**: Using TensorOperations.jl with optimal ordering
- **Environment caching**: O(N) complexity per sweep for both DMRG and TDVP
- **Minimal memory allocation**: In-place operations where possible
- **Scalability**: Successfully tested on systems up to N=500 sites with χ=1000

### Exact Diagonalization:
- **Sparse matrices**: Automatic use for large Hilbert spaces (D > 20)
- **Optimized eigensolvers**: Arpack for partial spectrum, LAPACK for full diagonalization
- **Parallel BLAS**: Multi-threaded linear algebra operations
- **Memory efficient**: Sparse storage reduces memory by ~100× for typical Hamiltonians
- **Fast time evolution**: Two-stage algorithm (diagonalize once, evolve many times)

### Scalability Guide:

**ED:**
```
N=10: D=1,024    → ~8 MB,   3 sec     ✅ Perfect for development
N=12: D=4,096    → ~130 MB, 2 min     ✅ Good for benchmarking
N=14: D=16,384   → ~4 GB,   2 hours   ⚠️ Maximum practical
N=16: D=65,536   → ~68 GB,  impractical ❌
```

**DMRG/TDVP:**
```
N=50,  χ=100  → ~10 MB,  minutes    ✅ Standard
N=100, χ=200  → ~40 MB,  ~hour      ✅ Large
N=500, χ=1000 → ~1 GB,   hours      ✅ Very large
```

---

## Advanced Features

### Long-Range Interactions via FSM (Tensor Networks)
Implements power-law interactions using sum-of-exponentials decomposition, enabling efficient MPO construction:

```
1/r^α ≈ Σᵢ νᵢ λᵢʳ
```

Reduces bond dimension from O(N) to O(log N) while maintaining accuracy.

### Exact Power-Law Interactions (ED)
ED implements long-range interactions exactly without approximation:

```
H = J Σᵢ<ⱼ σᵢσⱼ / |i-j|^α
```

Perfect for benchmarking sum-of-exponentials approximations used in TN methods.

### Time Evolution Algorithms

**TDVP (Tensor Networks):**
- Two-site + one-site sweeps
- Krylov exponential integrator
- Adaptive time stepping (optional)

**ED Time Evolution:**
- Two-stage algorithm:
  1. Diagonalize H = VDV† once (expensive)
  2. Evolve |ψ(t)⟩ = V exp(-iDt) V†|ψ(0)⟩ (cheap)
- Exact unitary evolution (no Trotter errors)
- Can compute ψ(t) for any t efficiently

### Time-Based Queries for TDVP
```julia
# Load state at specific physical time
mps, extra_data, actual_time = load_mps_at_time(run_dir, time=1.5)
```

### Hash-Based Data Management
```julia
# Find all runs with same configuration
config = JSON.parsefile("config.json")
runs = find_runs_by_config(config, base_dir="data")

# Query system (preferred)
results = query("sim", algorithm="dmrg", model_name="heisenberg")

# Load specific run
mps, data = load_mps_sweep(results[1]["run_dir"], sweep)
```

---

## Algorithm Details

### DMRG (Density Matrix Renormalization Group)
- Two-site algorithm for ground state search
- Lanczos eigensolver with Krylov subspace dimension control
- Adaptive bond dimension with SVD truncation
- Energy variance monitoring for convergence
- Best for: Ground states of large 1D systems (N > 14)

### TDVP (Time-Dependent Variational Principle)
- Two-site + one-site algorithm for real/imaginary time evolution
- Krylov exponential integrator for matrix exponentials
- Local basis optimization at each time step
- Compatible with both unitary and non-unitary evolution
- Best for: Time dynamics of large 1D systems (N > 14)

### Exact Diagonalization (ED)

**ED Spectrum:**
- Full diagonalization of Hamiltonian in complete Hilbert space
- Returns all eigenvalues and eigenvectors
- No approximations (numerically exact)
- Hilbert space dimension: D = (2S+1)^N for spin-S
- Best for: Small systems (N ≤ 12), full spectrum, benchmarking

**ED Time Evolution:**
- Two-stage algorithm:
  1. Diagonalize H = VDV† once (expensive, O(D³))
  2. Evolve |ψ(t)⟩ = V exp(-iDt) V†|ψ(0)⟩ (cheap, O(D²) per step)
- Exact unitary evolution (no Trotter errors)
- Can compute ψ(t) for any t efficiently after diagonalization
- Best for: Exact dynamics of small systems, benchmarking TDVP

**Scalability:**
```
Spin-1/2 Systems:
N=10: D=1,024    → ~8 MB,   3 sec      ✅ Development
N=12: D=4,096    → ~130 MB, 2 min      ✅ Benchmarking
N=14: D=16,384   → ~4 GB,   2 hours    ⚠️ Maximum
N=16: D=65,536   → ~68 GB,  impractical ❌

Spin-1 Systems:
N=8:  D=6,561    → ~400 MB, ~10 min    ✅
N=10: D=59,049   → ~30 GB,  hours      ⚠️
```

**When to use ED:**
- Benchmarking TN methods (N=10-12)
- Need exact results or full spectrum
- Study excited state physics
- Small system sizes only

### To be added soon
- A positive tensor network approach for simulating open quantum many-body systems and thermal states
- Based on Phys. Rev. Lett. 116, 237201 (2016) 

---

## Testing

```julia
using Pkg
Pkg.activate(".")
Pkg.test()
```

Test suite includes:
- Unit tests for tensor operations
- Algorithm convergence tests (DMRG, TDVP, ED)
- Observable calculation validation
- Configuration parsing tests
- Catalog and query system tests

---

## Contributing

Contributions are welcome! Areas of particular interest:
- New algorithms (e.g., infinite DMRG, finite-temperature methods, PEPS)
- Additional physical models and observables
- Performance optimizations for ED and TN methods
- Documentation improvements and examples
- Benchmarking studies comparing ED and TN methods

---

## Citation

If you use TNCodebase in your research, please cite:

```bibtex
@software{tncodbase2025,
  author = {Nishan Ranabhat},
  title = {TNCodebase: Comprehensive Framework for Quantum Many-Body Simulations},
  year = {2025},
  url = {https://github.com/yourusername/TNCodebase},
  note = {Tensor network methods and exact diagonalization for quantum many-body physics}
}
```

---

## Related Methods

The algorithms implemented in TNCodebase are directly applicable to:

**Condensed Matter Physics:**
- Frustrated magnets and spin liquids
- Topological phases and edge states
- Quantum phase transitions
- Spectroscopy and dynamical structure factors

**Quantum Information:**
- Entanglement dynamics
- Quantum circuits and gates
- Quantum state preparation

**AMO Physics:**
- Cold atoms in optical lattices
- Rydberg atom arrays
- Light-matter interactions (via spin-boson models)

**Method Comparison:**
- **Exact Diagonalization** is particularly useful for:
  - Benchmarking approximate tensor network results
  - Small system physics and detailed spectral analysis
  - Method development and algorithm validation
  - Understanding finite-size effects
  
- The **TDVP algorithm** is mathematically equivalent to TD-DMRG in appropriate limits

---

## Documentation

Comprehensive documentation is available in the `docs/` directory:

### User Guides:
- **ED_USER_GUIDE.md** - Using exact diagonalization (for researchers)
- **QUERY_SYSTEM_GUIDE.md** - Complete query API and examples
- **model_building.md** - Creating custom models
- **state_building.md** - State preparation

### Developer Guides:
- **ED_ARCHITECTURE_GUIDE.md** - ED internals and extending the code
- **CATALOG_SYSTEM_ARCHITECTURE.md** - Catalog building system
- **CATALOG_QUERY_INTEGRATION.md** - Complete workflows

### Quick References:
- **QUICK_REFERENCE.md** - Cheat sheet for common operations

---

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

## Contact

**Nishan Ranabhat**  
Email: nishanranabhat101@gmail.com  
GitHub: [@NishanRanabhat](https://github.com/NishanRanabhat)

---

## Acknowledgments

- Developed as part of PhD research at SISSA and postdoctoral work at UMBC
- Algorithms based on foundational work by:
  - White (1992) - DMRG
  - Haegeman et al. (2011) - TDVP
  - Lanczos (1950) - Exact diagonalization methods
- Built using Julia's ecosystem: TensorOperations.jl, JLD2.jl, JSON.jl, Arpack.jl, LinearAlgebra.jl

---

**Status**: Under active development | Contributions welcome | Documented and tested

**Version**: 1.0.0 (January 2025)  
**Features**: DMRG ✅ | TDVP ✅ | ED Spectrum ✅ | ED Time Evolution ✅ | Query System ✅ | Catalog System ✅
