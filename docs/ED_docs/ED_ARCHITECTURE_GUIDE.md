# EXACT DIAGONALIZATION (ED) - ARCHITECTURE GUIDE

## 📋 Table of Contents
1. [Overview](#overview)
2. [Module Structure](#module-structure)
3. [Data Flow](#data-flow)
4. [Basis Construction](#basis-construction)
5. [Operator Embedding](#operator-embedding)
6. [Hamiltonian Building](#hamiltonian-building)
7. [Solver Algorithms](#solver-algorithms)
8. [Time Evolution](#time-evolution)
9. [Observable Calculations](#observable-calculations)
10. [Adding New Features](#adding-new-features)

---

## Overview

The ED system consists of **8 interconnected modules** that transform a high-level config into eigenvalues/eigenvectors or time-evolved states.

### Design Philosophy

1. **Separation of concerns** - Each file has one responsibility
2. **Composability** - Functions combine to build complex operations
3. **Sparse by default** - Use sparse matrices for efficiency
4. **Config-driven** - Everything from JSON config
5. **Parallel to TN** - Similar API to DMRG/TDVP where possible

### Architecture Layers

```
Layer 4: High-level interface
├── config.json
└── run_simulation_from_config()

Layer 3: Algorithms
├── ed_spectrum
├── ed_time_evolution
└── ed_ground_state

Layer 2: Solvers
├── solve_spectrum()
├── solve_ground_state()
└── time_evolution()

Layer 1: Construction
├── build_H_spin()
├── build_H_spinboson()
└── embed_operator()

Layer 0: Primitives
├── Pauli matrices
├── Boson operators
└── Tensor products
```

---

## Module Structure

### File Organization

```
src/ED/
├── ed_operators.jl         # Primitive operators (σˣ, σʸ, σᶻ, b, b†)
├── ed_basis.jl             # Hilbert space embedding
├── ed_terms.jl             # Term types (nearest-neighbor, power-law, etc.)
├── ed_hamiltonian.jl       # Hamiltonian assembly
├── ed_models.jl            # Prebuilt model generators
├── ed_solver.jl            # Eigensolvers & time evolution
├── ed_states.jl            # Initial state preparation
└── ed_observables.jl       # Observable calculations
```

### Module Dependencies

```
ed_operators.jl
    ↓
ed_basis.jl ←─────────┐
    ↓                 │
ed_terms.jl           │
    ↓                 │
ed_hamiltonian.jl     │
    ↓                 │
ed_models.jl          │
    ↓                 │
ed_solver.jl          │
    ↓                 │
ed_states.jl ─────────┤
    ↓                 │
ed_observables.jl ────┘
```

### Detailed Module Breakdown

#### 1. **ed_operators.jl** (183 lines)

**Purpose:** Define primitive quantum operators

**Key functions:**
```julia
spin_operators(S::Real) -> (Sx, Sy, Sz, S_plus, S_minus, Id)
boson_operators(nmax::Int) -> (b, b_dag, n_op, Id)
```

**What it provides:**
- Spin-S operators as matrices
- Boson ladder operators (b, b†)
- Identity operators

**Example:**
```julia
Sx, Sy, Sz, Sp, Sm, I = spin_operators(0.5)
# Sx = [0  1; 1  0] / 2
# Sy = [0 -im; im 0] / 2
# Sz = [1  0; 0 -1] / 2
```

#### 2. **ed_basis.jl** (400 lines)

**Purpose:** Embed local operators into full Hilbert space

**Key functions:**
```julia
embed_operator(op, site, N, d) -> Matrix
embed_two_site(op1, op2, i, j, N, d) -> Matrix
embed_all_pairs(op1, op2, N, d) -> Matrix
embed_boson_spin(b_op, spin_op, site, config) -> Matrix
```

**What it does:**
- Takes local operator (e.g., 2×2 matrix)
- Embeds in full Hilbert space (e.g., 1024×1024)
- Handles tensor products: I ⊗ ... ⊗ op ⊗ ... ⊗ I

**Example:**
```julia
# Embed σᶻ at site 3 in 10-site chain
Sz_3 = embed_operator(Sz, 3, 10, 2)
# Returns 1024 × 1024 matrix
```

**Architecture:**
```julia
function embed_operator(op::AbstractMatrix, site::Int, N::Int, d::Int)
    # 1. Create identity chain
    #    I ⊗ I ⊗ ... ⊗ I
    
    # 2. Replace site'th position with op
    #    I ⊗ ... ⊗ op ⊗ ... ⊗ I
    
    # 3. Return full space operator
end
```

#### 3. **ed_terms.jl** (310 lines)

**Purpose:** Define interaction term types

**Key types:**
```julia
abstract type EDTerm end

struct EDField <: EDTerm
    operator::Symbol  # :X, :Y, or :Z
    strength::Float64
end

struct EDNearestNeighbor <: EDTerm
    op1::Symbol
    op2::Symbol
    coupling::Float64
end

struct EDPowerLaw <: EDTerm
    op1::Symbol
    op2::Symbol
    coupling::Float64
    alpha::Float64
end
```

**What it provides:**
- Structured representation of terms
- Helper constructors

**Example:**
```julia
# Field term: h Σᵢ σˣᵢ
field = EDField(:X, 0.5)

# Nearest-neighbor: J Σᵢ σᶻᵢσᶻᵢ₊₁
nn = EDNearestNeighbor(:Z, :Z, 1.0)

# Power-law: J Σᵢ<ⱼ σᶻᵢσᶻⱼ/|i-j|^α
pl = EDPowerLaw(:Z, :Z, 1.0, 2.0)
```

#### 4. **ed_hamiltonian.jl** (103 lines)

**Purpose:** Assemble Hamiltonian from terms

**Key functions:**
```julia
build_H_spin(N, S, terms) -> SparseMatrixCSC
build_H_spinboson(config, terms) -> SparseMatrixCSC
```

**What it does:**
1. Loop over terms
2. For each term, embed operators
3. Sum all contributions
4. Return sparse Hamiltonian matrix

**Example:**
```julia
terms = [
    EDNearestNeighbor(:Z, :Z, 1.0),  # Ising coupling
    EDField(:X, 0.5)                  # Transverse field
]

H = build_H_spin(10, 0.5, terms)
# Returns 1024 × 1024 sparse matrix
```

**Architecture:**
```julia
function build_H_spin(N::Int, S::Real, terms::Vector{EDTerm})
    d = Int(2S + 1)
    D = d^N
    
    H = spzeros(ComplexF64, D, D)
    
    for term in terms
        if term isa EDField
            # Add Σᵢ σᵢ
            H += embed_field_term(term, N, d)
        elseif term isa EDNearestNeighbor
            # Add Σᵢ σᵢ σᵢ₊₁
            H += embed_nn_term(term, N, d)
        # ... other terms
        end
    end
    
    return H
end
```

#### 5. **ed_models.jl** (342 lines)

**Purpose:** Generate term vectors for prebuilt models

**Key functions:**
```julia
_get_tfi_terms(J, h, coupling_dir, field_dir) -> Vector{EDTerm}
_get_heisenberg_terms(Jx, Jy, Jz, hx, hy, hz) -> Vector{EDTerm}
_get_lri_terms(J, h, alpha, ...) -> Vector{EDTerm}
build_H_from_config(config) -> SparseMatrixCSC
```

**What it does:**
- Translates model name + parameters → EDTerm vector
- Parallel to TN's channel-based approach
- Config-driven Hamiltonian construction

**Example:**
```julia
# Heisenberg model
terms = _get_heisenberg_terms(1.0, 1.0, 1.0, 0.0, 0.0, 0.0)
# Returns:
# [
#   EDNearestNeighbor(:X, :X, 1.0),
#   EDNearestNeighbor(:Y, :Y, 1.0),
#   EDNearestNeighbor(:Z, :Z, 1.0),
#   EDField(:X, 0.0),
#   EDField(:Y, 0.0),
#   EDField(:Z, 0.0)
# ]
```

**Config-based usage:**
```julia
config = Dict(
    "system" => Dict("type" => "spin", "N" => 10),
    "model" => Dict(
        "name" => "heisenberg",
        "params" => Dict("Jx" => 1.0, "Jy" => 1.0, "Jz" => 1.0)
    )
)

H = build_H_from_config(config)
```

#### 6. **ed_solver.jl** (537 lines)

**Purpose:** Eigensolvers and time evolution algorithms

**Key functions:**
```julia
solve_ground_state(H; use_sparse=true) -> (E0, psi0)
solve_spectrum(H, n_states) -> (energies, states)
prepare_time_evolution(H, psi0) -> EVData
evolve_to_time(ev_data, t) -> psi_t
```

**Algorithms:**
- Dense diagonalization (small systems)
- Sparse diagonalization (Arpack, large systems)
- Time evolution via eigendecomposition

**Architecture:**
```julia
# Ground state
function solve_ground_state(H; use_sparse=true)
    if use_sparse && issparse(H) && size(H,1) > 20
        # Use Arpack (iterative, sparse)
        vals, vecs = eigs(H, nev=1, which=:SR)
        E0 = real(vals[1])
        psi0 = vecs[:, 1]
    else
        # Use LAPACK (direct, dense)
        eig = eigen(Hermitian(Matrix(H)))
        idx = argmin(real(eig.values))
        E0 = real(eig.values[idx])
        psi0 = eig.vectors[:, idx]
    end
    
    return E0, psi0
end

# Full spectrum
function solve_spectrum(H, n_states)
    if n_states == size(H,1)
        # Full diagonalization
        eig = eigen(Hermitian(Matrix(H)))
        return eig.values, eig.vectors
    else
        # Partial spectrum (Arpack)
        vals, vecs = eigs(H, nev=n_states, which=:SR)
        return real(vals), vecs
    end
end

# Time evolution
function prepare_time_evolution(H, psi0)
    # Diagonalize H = V D V†
    eig = eigen(Hermitian(Matrix(H)))
    E = real(eig.values)
    V = eig.vectors
    
    # Project psi0 onto eigenbasis
    c = V' * psi0
    
    return EVData(E, V, c)
end

function evolve_to_time(ev_data::EVData, t::Real)
    # |ψ(t)⟩ = Σᵢ cᵢ exp(-iEᵢt) |Eᵢ⟩
    #        = V × [exp(-iE₀t), ...] × c
    
    phases = exp.(-im * ev_data.E * t)
    c_t = ev_data.c .* phases
    psi_t = ev_data.V * c_t
    
    return psi_t
end
```

#### 7. **ed_states.jl** (672 lines)

**Purpose:** Prepare initial states for time evolution

**Key functions:**
```julia
build_initial_state_from_config(config) -> Vector{ComplexF64}
build_polarized_state(N, S, direction, eigenstate) -> Vector
build_neel_state(N, S) -> Vector
build_domain_wall_state(N, S, position) -> Vector
```

**What it provides:**
- Prebuilt states (polarized, Néel, domain wall, etc.)
- Random states
- Product states
- Config-driven state construction

**Example:**
```julia
# All spins up
psi = build_polarized_state(10, 0.5, :Z, 1)

# Néel state
psi = build_neel_state(10, 0.5)

# From config
config = Dict(
    "system" => Dict("type" => "spin", "N" => 10),
    "state" => Dict(
        "type" => "prebuilt",
        "name" => "polarized",
        "params" => Dict("spin_direction" => "Z", "eigenstate" => 1)
    )
)
psi = build_initial_state_from_config(config)
```

#### 8. **ed_observables.jl** (983 lines)

**Purpose:** Calculate observables on states

**Key functions:**
```julia
calculate_observable(obs_config, state_data) -> Dict
calculate_entanglement_entropy(psi, bond, d, N) -> Float64
calculate_correlation_function(psi, op, sites, d, N) -> Float64
calculate_magnetization(psi, op, site, d, N) -> Float64
```

**What it does:**
- Takes state vector (or collection)
- Computes expectation values
- Supports various observable types

**Example:**
```julia
# Entanglement entropy
S = calculate_entanglement_entropy(psi, 5, 2, 10)

# Magnetization
⟨Sz⟩ = calculate_magnetization(psi, :Z, 1, 2, 10)

# Correlation
⟨SzᵢSzⱼ⟩ = calculate_correlation_function(psi, :Z, (1, 5), 2, 10)
```

---

## Data Flow

### ED Spectrum Flow

```
1. User creates config
   ↓
2. run_simulation_from_config(config)
   ↓
3. build_H_from_config(config)
   ├─ Extract model name & params
   ├─ _get_X_terms(params...) → terms::Vector{EDTerm}
   └─ build_H_spin(N, S, terms) → H::SparseMatrix
   
4. solve_spectrum(H, all_states)
   ├─ eigen(Hermitian(Matrix(H)))
   └─ Returns (eigenvalues, eigenvectors)
   
5. Save results
   ├─ results.jld2: eigenvalues, eigenvectors
   └─ metadata.json: ground_energy, spectral_gap, etc.
   
6. Catalog entry appended
```

### ED Time Evolution Flow

```
1. User creates config (with initial state)
   ↓
2. run_simulation_from_config(config)
   ↓
3. build_H_from_config(config) → H
   ↓
4. build_initial_state_from_config(config) → psi0
   ↓
5. prepare_time_evolution(H, psi0)
   ├─ Diagonalize H = V D V†
   ├─ Project psi0 → c = V† psi0
   └─ Store (E, V, c)
   
6. for step in 1:n_steps
   │   t = step * dt
   │   psi_t = evolve_to_time(ev_data, t)
   │   save(step_XXX.jld2, psi_t, t)
   └─
   
7. Catalog entry appended
```

### Observable Calculation Flow

```
1. User creates observable config (references simulation)
   ↓
2. run_observable_calculation_from_config(obs_config)
   ↓
3. Load simulation results
   ├─ ED spectrum: load eigenvalues, eigenvectors
   └─ ED time evolution: load states at time steps
   
4. For each selected state:
   │   calculate_observable(obs_type, psi, params)
   │   ├─ calculate_entanglement_entropy(psi, bond)
   │   ├─ calculate_correlation_function(psi, op, sites)
   │   └─ calculate_magnetization(psi, op, site)
   └─
   
5. Save observables.jld2
   ├─ observable_values: Vector or Matrix
   ├─ energies (if spectrum) or times (if evolution)
   └─ parameters
   
6. Observable catalog entry appended
```

---

## Basis Construction

### Hilbert Space Structure

**Spin-only system:**
```
|ψ⟩ = Σ_{s₁,...,sₙ} c_{s₁...sₙ} |s₁⟩ ⊗ ... ⊗ |sₙ⟩

State vector: ψ[i] where i encodes (s₁, ..., sₙ)
Dimension: D = d^N, d = 2S+1
```

**Spin-boson system:**
```
|ψ⟩ = Σ_{n,s₁,...,sₙ} c_{n,s₁...sₙ} |n⟩ ⊗ |s₁⟩ ⊗ ... ⊗ |sₙ⟩

State vector: ψ[i] where i encodes (n, s₁, ..., sₙ)
Dimension: D = (nmax+1) × d^N
```

### Index Mapping

**Lexicographic ordering:**
```julia
# For N=3 spins, S=1/2 (d=2)
# States: |000⟩, |001⟩, |010⟩, |011⟩, |100⟩, |101⟩, |110⟩, |111⟩
# Indices:   0      1      2      3      4      5      6      7

function state_to_index(s₁, s₂, ..., sₙ)
    # s₁, ..., sₙ ∈ {0, 1, ..., d-1}
    index = s₁ + s₂*d + s₃*d² + ... + sₙ*d^(N-1)
    return index + 1  # Julia 1-indexed
end
```

**Example:**
```julia
# State |101⟩ = |↓↑↓⟩
s₁, s₂, s₃ = 1, 0, 1  # (down, up, down)
index = 1 + 0*2 + 1*4 + 1 = 6
```

### Operator Embedding Algorithm

**Single-site operator:**
```julia
function embed_operator(op::AbstractMatrix, site::Int, N::Int, d::Int)
    # op: d × d matrix
    # site: position (1 to N)
    # Returns: D × D matrix, D = d^N
    
    # Method 1: Direct tensor product (small systems)
    if N <= 8
        result = sparse(I(d))  # Start with first site
        
        for i in 2:N
            if i == site
                result = kron(result, op)
            else
                result = kron(result, I(d))
            end
        end
        
        return result
    end
    
    # Method 2: Sparse construction (large systems)
    # Only store non-zero elements
    I_sparse = sparse(1.0I(d))
    
    # Build list of matrices to kron
    matrices = [i == site ? op : I_sparse for i in 1:N]
    
    # Kronecker product
    result = kron(matrices...)
    
    return result
end
```

**Two-site operator:**
```julia
function embed_two_site(op1::AbstractMatrix, op2::AbstractMatrix,
                       i::Int, j::Int, N::Int, d::Int)
    # op1 at site i, op2 at site j
    # i < j assumed
    
    result = sparse(I(d))
    
    for site in 2:N
        if site == i
            result = kron(result, op1)
        elseif site == j
            result = kron(result, op2)
        else
            result = kron(result, I(d))
        end
    end
    
    return result
end
```

---

## Operator Embedding

### Sparse Matrix Strategy

**Why sparse?**
```julia
# Dense matrix (N=12)
D = 2^12 = 4096
memory_dense = D^2 * 16 bytes = 268 MB

# Sparse matrix (typical 1% nonzeros)
nonzeros = D^2 * 0.01 = 168,000
memory_sparse = 168,000 * (16 + 8) bytes = 4 MB

# 67× memory saving!
```

**Implementation:**
```julia
using SparseArrays

# Always use sparse identity
I_d = sparse(1.0I(d))

# Sparse Pauli matrices
Sx_sparse = sparse([0.0 1.0; 1.0 0.0] / 2)
Sy_sparse = sparse([0.0 -im; im 0.0] / 2)
Sz_sparse = sparse([1.0 0.0; 0.0 -1.0] / 2)
```

### Kronecker Products

**Julia's `kron()` preserves sparsity:**
```julia
A = sparse([1.0 0.0; 0.0 1.0])
B = sparse([0.0 1.0; 1.0 0.0])

C = kron(A, B)  # Still sparse!
```

**For multiple products:**
```julia
# Bad: iterative kron (inefficient)
result = A
for mat in matrices
    result = kron(result, mat)
end

# Good: single kron call
result = kron(A, B, C, D, ...)  # More efficient

# Best: Use varargs
result = kron(matrices...)
```

---

## Hamiltonian Building

### Assembly Algorithm

```julia
function build_H_spin(N::Int, S::Real, terms::Vector{EDTerm})
    d = Int(2S + 1)
    D = d^N
    
    # Pre-allocate sparse matrix
    H = spzeros(ComplexF64, D, D)
    
    # Get operators once
    Sx, Sy, Sz, Sp, Sm, Id = spin_operators(S)
    op_dict = Dict(:X => Sx, :Y => Sy, :Z => Sz,
                   :plus => Sp, :minus => Sm)
    
    # Process each term
    for term in terms
        if term isa EDField
            # Single-site: h Σᵢ σⁱ
            op = op_dict[term.operator]
            for site in 1:N
                H += term.strength * embed_operator(op, site, N, d)
            end
            
        elseif term isa EDNearestNeighbor
            # Two-site: J Σᵢ σⁱ σⁱ⁺¹
            op1 = op_dict[term.op1]
            op2 = op_dict[term.op2]
            for i in 1:(N-1)
                H += term.coupling * embed_two_site(op1, op2, i, i+1, N, d)
            end
            
        elseif term isa EDPowerLaw
            # All pairs: J Σᵢ<ⱼ σⁱσʲ / |i-j|^α
            op1 = op_dict[term.op1]
            op2 = op_dict[term.op2]
            for i in 1:N
                for j in (i+1):N
                    distance = j - i
                    coupling = term.coupling / (distance^term.alpha)
                    H += coupling * embed_two_site(op1, op2, i, j, N, d)
                end
            end
        end
    end
    
    return H
end
```

### Optimization: Precompute Embeddings

For repeated use (e.g., time evolution with same H):
```julia
# Cache embedded operators
struct CachedOperators
    Sx_embedded::Vector{SparseMatrixCSC}  # Sx at each site
    Sy_embedded::Vector{SparseMatrixCSC}
    Sz_embedded::Vector{SparseMatrixCSC}
end

function precompute_operators(N, d, S)
    Sx, Sy, Sz, _, _, _ = spin_operators(S)
    
    Sx_cache = [embed_operator(Sx, i, N, d) for i in 1:N]
    Sy_cache = [embed_operator(Sy, i, N, d) for i in 1:N]
    Sz_cache = [embed_operator(Sz, i, N, d) for i in 1:N]
    
    return CachedOperators(Sx_cache, Sy_cache, Sz_cache)
end
```

---

## Solver Algorithms

### Dense vs Sparse

**Decision tree:**
```julia
function choose_solver(H)
    D = size(H, 1)
    
    if D < 20
        return :dense  # Always use dense for small systems
    elseif issparse(H) && nnz(H) / D^2 < 0.1
        return :sparse  # Use sparse if sparsity > 90%
    else
        return :dense  # Dense if not sparse enough
    end
end
```

### Ground State: Arpack

**Using Arpack.jl:**
```julia
using Arpack

function solve_ground_state_sparse(H)
    # Find lowest eigenvalue
    vals, vecs, info = eigs(H, 
        nev=1,              # Number of eigenvalues
        which=:SR,          # Smallest Real part
        tol=1e-10,          # Convergence tolerance
        maxiter=300         # Max iterations
    )
    
    if info != 0
        @warn "Arpack convergence issue: info=$info"
    end
    
    E0 = real(vals[1])
    psi0 = vecs[:, 1]
    psi0 = psi0 / norm(psi0)
    
    return E0, psi0
end
```

**Convergence:**
- Typically converges in 50-100 iterations
- Tolerance 1e-10 is usually sufficient
- Convergence issues rare for Hermitian H

### Full Spectrum: LAPACK

**Using LinearAlgebra.jl:**
```julia
using LinearAlgebra

function solve_spectrum_dense(H)
    # Ensure Hermitian for efficiency
    H_herm = Hermitian(Matrix(H))
    
    # Full eigendecomposition
    eig = eigen(H_herm)
    
    # Sort by energy (should already be sorted)
    perm = sortperm(real(eig.values))
    
    energies = real(eig.values[perm])
    states = eig.vectors[:, perm]
    
    return energies, states
end
```

**LAPACK details:**
- Uses `DSYEV` or `ZHEEV` (Hermitian eigensolvers)
- O(D³) complexity
- Highly optimized BLAS/LAPACK
- Parallel via BLAS threads

---

## Time Evolution

### Two-Stage Design

**Stage 1: Preparation (expensive, once)**
```julia
struct EVData
    E::Vector{Float64}         # Eigenvalues
    V::Matrix{ComplexF64}      # Eigenvectors
    c::Vector{ComplexF64}      # Initial state coefficients
end

function prepare_time_evolution(H, psi0)
    # Diagonalize: H = V D V†
    eig = eigen(Hermitian(Matrix(H)))
    E = real(eig.values)
    V = eig.vectors
    
    # Project initial state
    c = V' * psi0  # Coefficients in energy basis
    
    return EVData(E, V, c)
end
```

**Stage 2: Evolution (cheap, each step)**
```julia
function evolve_to_time(ev_data::EVData, t::Real)
    # |ψ(t)⟩ = Σᵢ cᵢ exp(-iEᵢt) |Eᵢ⟩
    
    # Compute phase factors
    phases = exp.(-im * ev_data.E * t)
    
    # Apply phases
    c_t = ev_data.c .* phases
    
    # Transform back to position basis
    psi_t = ev_data.V * c_t
    
    return psi_t
end
```

**Cost analysis:**
```julia
# Preparation:
# - Diagonalization: O(D³) ~ hours for D=16384
# - Projection: O(D²) ~ seconds

# Evolution per step:
# - Phase computation: O(D) ~ microseconds
# - Matrix-vector: O(D²) ~ milliseconds

# For 1000 steps: preparation dominates!
```

### Why This Design?

**Alternative: Trotter decomposition**
```julia
# Bad for ED:
psi_{n+1} = exp(-iH dt) psi_n
          ≈ exp(-iH₁ dt) exp(-iH₂ dt) psi_n  # Trotter

# Problems:
# - Requires many matrix exponentials
# - Accumulates Trotter errors
# - Slower than eigendecomposition
```

**Our approach:**
- ✅ One-time diagonalization
- ✅ Exact evolution (no Trotter)
- ✅ Fast per-step cost
- ✅ Can get ψ(t) for any t

### Consistency with TDVP

**Interface design:**
```julia
# Both algorithms save:
data/[algorithm]/[run_id]/
├── step_001.jld2  # State at t=dt
├── step_002.jld2  # State at t=2dt
└── ...

# Observable calculations work identically:
obs_config = Dict(
    "simulation" => config,  # Works for both ED and TDVP
    "observable" => ...,
    "analysis" => Dict(
        "step_selection" => Dict("type" => "all")
    )
)
```

---

## Observable Calculations

### Architecture

```julia
# Dispatcher
function calculate_observable(obs_config, state_data)
    obs_type = obs_config["observable"]["type"]
    
    if obs_type == "entanglement_entropy"
        return calculate_entanglement_entropy(state_data, obs_config)
    elseif obs_type == "correlation_function"
        return calculate_correlation_function(state_data, obs_config)
    # ... etc
    end
end
```

### Entanglement Entropy

**Algorithm:**
```julia
function calculate_entanglement_entropy(psi::Vector, bond::Int, d::Int, N::Int)
    # 1. Reshape into matrix
    #    ψ[s₁...sₙ] → ψ[{s₁...s_bond}, {s_{bond+1}...sₙ}]
    
    D_left = d^bond
    D_right = d^(N - bond)
    
    psi_matrix = reshape(psi, D_left, D_right)
    
    # 2. SVD: ψ = U S V†
    #    Schmidt decomposition
    
    F = svd(psi_matrix)
    singular_values = F.S
    
    # 3. Entanglement entropy
    #    S = -Σᵢ λᵢ² log(λᵢ²)
    
    λ_squared = singular_values.^2
    λ_squared = λ_squared[λ_squared .> 1e-15]  # Filter numerical zeros
    
    S = -sum(λ_squared .* log.(λ_squared))
    
    return S
end
```

**Complexity:** O(D_left² × D_right) = O(d^(2*min(bond, N-bond)) × d^(N-min(bond,N-bond)))

### Correlation Functions

**Algorithm:**
```julia
function calculate_correlation_function(psi::Vector, op::Symbol, 
                                       sites::(Int,Int), d::Int, N::Int)
    i, j = sites
    
    # 1. Build operators
    Sx, Sy, Sz, _, _, _ = spin_operators(0.5)
    op_dict = Dict(:X => Sx, :Y => Sy, :Z => Sz)
    
    local_op = op_dict[op]
    
    # 2. Embed in full space
    Op_i = embed_operator(local_op, i, N, d)
    Op_j = embed_operator(local_op, j, N, d)
    
    # 3. Compute ⟨ψ| Op_i Op_j |ψ⟩
    
    # Method 1: Direct (small systems)
    if N <= 10
        result = real(psi' * Op_i * Op_j * psi)
    else
        # Method 2: Staged (large systems)
        temp = Op_j * psi
        temp = Op_i * temp
        result = real(dot(psi, temp))
    end
    
    return result
end
```

### Magnetization

**Algorithm:**
```julia
function calculate_magnetization(psi::Vector, op::Symbol, 
                                site::Int, d::Int, N::Int)
    # 1. Build and embed operator
    Sx, Sy, Sz, _, _, _ = spin_operators(0.5)
    op_dict = Dict(:X => Sx, :Y => Sy, :Z => Sz)
    
    local_op = op_dict[op]
    Op = embed_operator(local_op, site, N, d)
    
    # 2. Compute ⟨ψ| Op |ψ⟩
    result = real(dot(psi, Op * psi))
    
    return result
end
```

**Optimization for many sites:**
```julia
function calculate_magnetization_profile(psi::Vector, op::Symbol, 
                                        d::Int, N::Int)
    # Pre-embed operator at all sites
    ops = [embed_operator(op_matrix, i, N, d) for i in 1:N]
    
    # Calculate all expectation values
    profile = [real(dot(psi, Op * psi)) for Op in ops]
    
    return profile
end
```

---

## Adding New Features

### Adding a New Model

**Example: XXZ Model with Dzyaloshinskii-Moriya interaction**

**Step 1: Define term generator**
```julia
# In ed_models.jl

"""
XXZ + DM Model:
H = Jz Σᵢ σᶻᵢσᶻᵢ₊₁ + J_perp Σᵢ (σˣᵢσˣᵢ₊₁ + σʸᵢσʸᵢ₊₁) + D Σᵢ (σˣᵢσʸᵢ₊₁ - σʸᵢσˣᵢ₊₁)
"""
function _get_xxz_dm_terms(Jz::Real, J_perp::Real, D::Real)
    terms = EDTerm[
        # XXZ part
        EDNearestNeighbor(:Z, :Z, Jz),
        EDNearestNeighbor(:X, :X, J_perp),
        EDNearestNeighbor(:Y, :Y, J_perp)
    ]
    
    # DM part requires custom term type
    if D != 0
        push!(terms, EDDM(:X, :Y, D))      # σˣσʸ term
        push!(terms, EDDM(:Y, :X, -D))     # -σʸσˣ term
    end
    
    return terms
end
```

**Step 2: Define custom term type (if needed)**
```julia
# In ed_terms.jl

struct EDDM <: EDTerm
    op1::Symbol
    op2::Symbol
    coupling::Float64
end

# Constructor
function dm_term(op1::Symbol, op2::Symbol, coupling::Real)
    return EDDM(op1, op2, Float64(coupling))
end
```

**Step 3: Handle in Hamiltonian builder**
```julia
# In ed_hamiltonian.jl

function build_H_spin(N::Int, S::Real, terms::Vector{EDTerm})
    # ... existing code ...
    
    for term in terms
        # ... existing term types ...
        
        elseif term isa EDDM
            # DM interaction: special nearest-neighbor
            op1 = op_dict[term.op1]
            op2 = op_dict[term.op2]
            for i in 1:(N-1)
                H += term.coupling * embed_two_site(op1, op2, i, i+1, N, d)
            end
        end
    end
    
    return H
end
```

**Step 4: Add to config dispatcher**
```julia
# In ed_models.jl

function build_H_from_config(config::Dict)
    model_name = config["model"]["name"]
    params = config["model"]["params"]
    
    if model_name == "heisenberg"
        terms = _get_heisenberg_terms(...)
    elseif model_name == "xxz_dm"  # ← Add this
        Jz = params["Jz"]
        J_perp = params["J_perp"]
        D = params["D"]
        terms = _get_xxz_dm_terms(Jz, J_perp, D)
    # ... etc
    end
    
    H = build_H_spin(N, S, terms)
    return H
end
```

**Step 5: Use it!**
```julia
config = Dict(
    "system" => Dict("type" => "spin", "N" => 10),
    "model" => Dict(
        "name" => "xxz_dm",
        "params" => Dict(
            "Jz" => 1.0,
            "J_perp" => 0.5,
            "D" => 0.1
        )
    ),
    "algorithm" => Dict("type" => "ed_spectrum")
)

run_simulation_from_config(config)
```

### Adding a New Observable Type

**Example: Spin current**

**Step 1: Implement calculation**
```julia
# In ed_observables.jl

"""
Calculate spin current between sites i and i+1:
J_spin = i⟨ψ| (S⁺ᵢS⁻ᵢ₊₁ - S⁻ᵢS⁺ᵢ₊₁) |ψ⟩
"""
function calculate_spin_current(psi::Vector, site::Int, 
                                d::Int, N::Int)
    # Get spin operators
    _, _, _, Sp, Sm, _ = spin_operators((d-1)/2)
    
    # Embed
    Sp_i = embed_operator(Sp, site, N, d)
    Sm_i = embed_operator(Sm, site, N, d)
    Sp_j = embed_operator(Sp, site+1, N, d)
    Sm_j = embed_operator(Sm, site+1, N, d)
    
    # Compute current
    temp1 = Sm_j * psi
    temp1 = Sp_i * temp1
    
    temp2 = Sp_j * psi
    temp2 = Sm_i * temp2
    
    J = im * (dot(psi, temp1) - dot(psi, temp2))
    
    return real(J)
end
```

**Step 2: Add to dispatcher**
```julia
# In ed_observables.jl

function calculate_observable(obs_config, state_data)
    obs_type = obs_config["observable"]["type"]
    
    if obs_type == "spin_current"  # ← Add this
        site = obs_config["observable"]["params"]["site"]
        
        if haskey(state_data, "states")
            # Multiple states (spectrum)
            results = []
            for psi in eachcol(state_data["states"])
                J = calculate_spin_current(psi, site, d, N)
                push!(results, J)
            end
            return Dict("spin_current" => results)
        else
            # Single state
            psi = state_data["state"]
            J = calculate_spin_current(psi, site, d, N)
            return Dict("spin_current" => J)
        end
    end
    
    # ... existing observables ...
end
```

**Step 3: Use it!**
```julia
obs_config = Dict(
    "simulation" => sim_config,
    "observable" => Dict(
        "type" => "spin_current",
        "params" => Dict("site" => 5)
    ),
    "analysis" => Dict(
        "state_selection" => Dict("type" => "all")
    )
)

run_observable_calculation_from_config(obs_config)
```

### Adding a New Initial State

**Example: W state**

**Step 1: Implement builder**
```julia
# In ed_states.jl

"""
Build W state: |W⟩ = (|100...⟩ + |010...⟩ + ... + |...001⟩) / √N
Equally weighted single-excitation state
"""
function build_w_state(N::Int, S::Real)
    @assert S == 0.5 "W state only defined for S=1/2"
    
    d = 2
    D = 2^N
    
    psi = zeros(ComplexF64, D)
    
    # Add each single-excitation configuration
    for site in 1:N
        # State with spin-up only at 'site'
        config = zeros(Int, N)
        config[site] = 1  # Spin up
        
        idx = state_to_index(config, d)
        psi[idx] = 1.0 / sqrt(N)
    end
    
    return psi
end

function state_to_index(config::Vector{Int}, d::Int)
    N = length(config)
    idx = 0
    for i in 1:N
        idx += config[i] * d^(i-1)
    end
    return idx + 1  # Julia 1-indexed
end
```

**Step 2: Add to config dispatcher**
```julia
# In ed_states.jl

function build_initial_state_from_config(config::Dict)
    state_type = config["state"]["type"]
    
    if state_type == "prebuilt"
        name = config["state"]["name"]
        
        if name == "w_state"  # ← Add this
            return build_w_state(N, S)
        elseif name == "polarized"
            # ... existing
        end
    end
    
    # ... rest
end
```

**Step 3: Use it!**
```julia
config = Dict(
    "system" => Dict("type" => "spin", "N" => 10),
    "model" => Dict("name" => "heisenberg", ...),
    "state" => Dict(
        "type" => "prebuilt",
        "name" => "w_state"
    ),
    "algorithm" => Dict("type" => "ed_time_evolution", ...)
)

run_simulation_from_config(config)
```

---

## Summary

### ED Architecture Highlights

✅ **Modular design** - 8 independent files  
✅ **Sparse matrices** - Efficient memory use  
✅ **Config-driven** - High-level interface  
✅ **Extensible** - Easy to add models/observables  
✅ **Exact** - No approximations  
✅ **Well-tested** - Validates other methods

### Module Responsibilities

| Module | Purpose | Key Functions |
|--------|---------|---------------|
| ed_operators.jl | Primitive ops | spin_operators(), boson_operators() |
| ed_basis.jl | Embedding | embed_operator(), embed_two_site() |
| ed_terms.jl | Term types | EDField, EDNearestNeighbor, EDPowerLaw |
| ed_hamiltonian.jl | H assembly | build_H_spin(), build_H_spinboson() |
| ed_models.jl | Model builders | _get_X_terms(), build_H_from_config() |
| ed_solver.jl | Algorithms | solve_spectrum(), evolve_to_time() |
| ed_states.jl | Initial states | build_X_state() |
| ed_observables.jl | Measurements | calculate_observable() |

### Extension Points

**To add:**
1. **New model** → ed_models.jl
2. **New term type** → ed_terms.jl + ed_hamiltonian.jl
3. **New observable** → ed_observables.jl
4. **New state** → ed_states.jl
5. **New system type** → ed_basis.jl + ed_hamiltonian.jl

### Performance Considerations

- **Sparse matrices** for all large systems
- **Arpack** for partial spectrum
- **LAPACK** for full spectrum
- **Cached embeddings** for repeated use
- **BLAS threading** for parallelism

---

**You now understand the complete ED architecture!** 🎉

**For usage:** See ED_USER_GUIDE.md  
**For examples:** See example files
