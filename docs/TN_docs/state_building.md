# State Building Guide

## Overview

TNCodebase provides a complete framework for constructing initial Matrix Product States (MPS) for simulations. The system is designed around:

1. **Site-based construction** - States built from local site tensors
2. **Config-driven specification** - Initial states defined through JSON configuration
3. **Prebuilt pattern library** - Common initial states (polarized, Neel, domain walls, etc.)
4. **Custom state flexibility** - Site-by-site manual specification

This design separates the physics (what quantum state to prepare) from the implementation (how to construct the MPS representation), enabling rapid prototyping of initial conditions for DMRG, TDVP, and other tensor network algorithms.

---

## Architecture

### Construction Flow

```
JSON Config → Sites Builder → Pattern Generator → State Tensor → MPS{T}
```

**Step 1: Sites Builder**
- `_build_sites_from_config()` creates array of site objects
- Handles homogeneous (all spins) and heterogeneous (spin-boson) systems
- Each site stores operators and precomputed eigenspectra

**Step 2: Pattern Generator**
- Prebuilt patterns: Template functions generate label arrays
- Custom patterns: User-specified labels parsed from config
- Random states: Bypass pattern generation

**Step 3: State Tensor Construction**
- `_state_tensor(site, label)` creates (1,d,1) tensor for each site
- Uses precomputed eigenvectors from site objects
- Efficient: No runtime diagonalization

**Step 4: MPS Assembly**
- `product_state()` assembles bond-dimension-1 MPS from tensors
- `random_state()` creates random MPS with specified bond dimension

### Key Design Features

**Efficiency:**
- Eigenspectra precomputed once per site type
- State tensors constructed via reshape (no copies)
- Product states have bond dimension 1 (minimal memory)

**Type Safety:**
- Parametric types `SpinSite{T}`, `BosonSite{T}`
- MPS inherits type from sites: `MPS{T}`
- Supports Float64, ComplexF64, etc.

**Modularity:**
- Sites independent of state patterns
- Patterns independent of MPS construction
- Easy to add new prebuilt states

---

## Site Types

Sites are the fundamental building blocks. Each site stores:
- Local Hilbert space dimension
- Operators (for observable calculations)
- Precomputed eigenspectra (for state construction)

### SpinSite{T}

**Structure:**
```julia
struct SpinSite{T} <: AbstractSite{T}
    dim::Int                        # Hilbert space dimension (2S+1)
    ops::Dict{Symbol,Matrix{T}}     # Operators: X, Y, Z, Sp, Sm, I
    spectra::Dict{Symbol,Tuple}     # Precomputed eigenvalues & eigenvectors
end
```

**Construction:**
```julia
spin_site = SpinSite(0.5, T=ComplexF64)  # Spin-1/2
spin_site = SpinSite(1.0, T=ComplexF64)     # Spin-1
```

**Parameters:**
- `S` - Spin value (0.5 for spin-1/2, 1.0 for spin-1, etc.)
- `T` - Data type (Float64 or ComplexF64)

**What it stores:**

1. **Dimension:**
   ```julia
   dim = 2S + 1
   ```
   For spin-1/2: dim = 2, for spin-1: dim = 3

2. **Operators:** Spin matrices in Cartesian basis
   ```julia
   ops[:X]  # Sx operator
   ops[:Y]  # Sy operator  
   ops[:Z]  # Sz operator
   ops[:Sp] # S+ ladder operator
   ops[:Sm] # S- ladder operator
   ops[:I]  # Identity
   ```

3. **Spectra:** Eigendecomposition of each operator
   ```julia
   spectra[:X] = (eigenvalues, eigenvectors)
   spectra[:Y] = (eigenvalues, eigenvectors)
   spectra[:Z] = (eigenvalues, eigenvectors)
   ```
   Eigenvalues sorted in ascending order

**Eigenstates:**

For spin-1/2 in Z basis:
- Eigenstate 1: Spin-up |↑⟩ (eigenvalue +1/2)
- Eigenstate 2: Spin-down |↓⟩ (eigenvalue -1/2)

For spin-1/2 in X basis:
- Eigenstate 1: |+⟩ (eigenvalue +1/2)
- Eigenstate 2: |-⟩ (eigenvalue -1/2)

---

### BosonSite{T}

**Structure:**
```julia
struct BosonSite{T} <: AbstractSite{T}
    dim::Int                # Truncated dimension (nmax + 1)
    op::Matrix{T}           # Number operator b†b
    eigvals::Vector{T}      # Eigenvalues: [0, 1, 2, ..., nmax]
    eigvecs::Matrix{T}      # Eigenvectors (Fock states)
end
```

**Construction:**
```julia
boson_site = BosonSite(10, T=Float64)  # Truncate at 10 bosons
```

**Parameters:**
- `nmax` - Maximum boson number (truncation)
- `T` - Data type

**What it stores:**

1. **Dimension:**
   ```julia
   dim = nmax + 1  # States: |0⟩, |1⟩, ..., |nmax⟩
   ```

2. **Number Operator:**
   ```julia
   op = b†b  # Diagonal with eigenvalues 0, 1, 2, ..., nmax
   ```

3. **Fock State Basis:**
   ```julia
   eigvals = [0, 1, 2, ..., nmax]
   eigvecs[:, n+1] = |n⟩  # Fock state with n bosons
   ```

**Fock States:**
- State 0: Vacuum |0⟩
- State 1: Single boson |1⟩
- State n: n bosons |n⟩

---

## State Tensor Construction

### The _state_tensor Function

**Purpose:** Create a (1, d, 1) MPS tensor for a single site in a specific eigenstate

**For SpinSite:**
```julia
function _state_tensor(site::SpinSite{T}, label::Tuple{Symbol,Int}) where T
    ax, k = label
    vals, vecs = site.spectra[ax]  # Get precomputed spectrum
    return reshape(vecs[:,k], 1, site.dim, 1)  # Reshape eigenvector
end
```

**Input:**
- `site` - SpinSite object with precomputed spectra
- `label` - `(direction, eigenstate_index)`
  - `direction`: `:X`, `:Y`, or `:Z`
  - `eigenstate_index`: 1 to dim (1 = lowest eigenvalue)

**Example:**
```julia
site = SpinSite(0.5)
tensor = _state_tensor(site, (:Z, 1))  # Spin-up along Z
# Returns (1, 2, 1) tensor: [1; 0] reshaped
```

**For BosonSite:**
```julia
function _state_tensor(site::BosonSite{T}, n::Int) where T
    return reshape(site.eigvecs[:, n+1], 1, site.dim, 1)
end
```

**Input:**
- `site` - BosonSite object
- `n` - Fock state number (0 to nmax)

**Example:**
```julia
site = BosonSite(10)
tensor = _state_tensor(site, 0)  # Vacuum state |0⟩
tensor = _state_tensor(site, 3)  # Three-boson state |3⟩
```

---

### Why (1, d, 1) Tensors?

**MPS Structure:**
```
Site 1:  [1 × d × χ]
Site 2:  [χ × d × χ]
Site 3:  [χ × d × χ]
...
Site N:  [χ × d × 1]
```

**Product States:**
For product states, bond dimension χ = 1:
```
Every tensor: [1 × d × 1]
```

**Contraction:**
```julia
|ψ⟩ = A[1]^(s₁) A[2]^(s₂) ... A[N]^(sₙ)
     = v₁ ⊗ v₂ ⊗ ... ⊗ vₙ
```

Each (1,d,1) tensor is just a local state vector reshaped:
```julia
reshape([v₁, v₂, ..., vₐ], 1, d, 1)
```

---

## Prebuilt States

Prebuilt states are template patterns for common initial conditions. All prebuilt states are **product states** (bond dimension 1).

### Spin-Only Prebuilt States

#### **1. Polarized State**

**Physics:** All spins aligned in same direction and eigenstate

**Quantum state:**
```
|ψ⟩ = |s⟩⊗|s⟩⊗...⊗|s⟩
```
where |s⟩ is the kth eigenstate of chosen axis

**Configuration:**
```json
{
  "state": {
    "type": "prebuilt",
    "name": "polarized",
    "params": {
      "spin_direction": "Z",
      "eigenstate": 1
    }
  }
}
```

**Parameters:**
- `spin_direction` - Quantization axis: "X", "Y", or "Z"
- `eigenstate` - Which eigenstate (1 = lowest eigenvalue, 2 = next, ...)

**Examples:**

**Spin-up in Z basis:**
```json
{"spin_direction": "Z", "eigenstate": 1}
```
Creates: |↑↑↑...↑⟩ (all spins in +Z direction)

**Spin-down in Z basis:**
```json
{"spin_direction": "Z", "eigenstate": 2}
```
Creates: |↓↓↓...↓⟩ (all spins in -Z direction)

**Polarized in +X direction:**
```json
{"spin_direction": "X", "eigenstate": 1}
```
Creates: |+⟩⊗|+⟩⊗...⊗|+⟩ where |+⟩ = (|↑⟩+|↓⟩)/√2

**Use cases:**
- Initial state for TDVP quench dynamics
- Ferromagnetic ground state approximation
- Maximum polarization states

---

#### **2. Neel State**

**Physics:** Alternating spin configuration (staggered magnetization)

**Quantum state:**
```
|ψ⟩ = |s₁⟩⊗|s₂⟩⊗|s₁⟩⊗|s₂⟩⊗...
```
Alternates between two eigenstates

**Configuration:**
```json
{
  "state": {
    "type": "prebuilt",
    "name": "neel",
    "params": {
      "spin_direction": "Z",
      "even_state": 1,
      "odd_state": 2
    }
  }
}
```

**Parameters:**
- `spin_direction` - Quantization axis
- `even_state` - Eigenstate for even-indexed sites (2, 4, 6, ...)
- `odd_state` - Eigenstate for odd-indexed sites (1, 3, 5, ...)

**Example:**

**Standard Neel in Z basis:**
```json
{"spin_direction": "Z", "even_state": 1, "odd_state": 2}
```
Creates: |↑↓↑↓↑↓...⟩

**Inverted Neel:**
```json
{"spin_direction": "Z", "even_state": 2, "odd_state": 1}
```
Creates: |↓↑↓↑↓↑...⟩

**Use cases:**
- Antiferromagnetic ground state approximation
- Studying order-disorder transitions
- Quench from magnetically ordered state

---

#### **3. Kink (Domain Wall)**

**Physics:** Single domain wall separating two polarized regions

**Quantum state:**
```
|ψ⟩ = |s₁⟩⊗...⊗|s₁⟩ ⊗ |s₂⟩⊗...⊗|s₂⟩
      \_____left_____/   \____right____/
```

**Configuration:**
```json
{
  "state": {
    "type": "prebuilt",
    "name": "kink",
    "params": {
      "spin_direction": "Z",
      "position": 20,
      "left_state": 1,
      "right_state": 2
    }
  }
}
```

**Parameters:**
- `spin_direction` - Quantization axis
- `position` - Kink location (sites 1 to position: left, rest: right)
- `left_state` - Eigenstate for left region
- `right_state` - Eigenstate for right region

**Example:**

**Single kink at center:**
```json
{"spin_direction": "Z", "position": 20, "left_state": 1, "right_state": 2}
```
For N=40: |↑↑...↑↓↓...↓⟩ with kink between sites 20 and 21

**Use cases:**
- Domain wall dynamics
- Soliton propagation
- Topological excitations

---

#### **4. Domain**

**Physics:** Localized domain of flipped spins in uniform background

**Quantum state:**
```
|ψ⟩ = |s_base⟩⊗...⊗|s_base⟩ ⊗ |s_flip⟩⊗...⊗|s_flip⟩ ⊗ |s_base⟩⊗...
      \______base______/      \____domain____/      \___base___/
```

**Configuration:**
```json
{
  "state": {
    "type": "prebuilt",
    "name": "domain",
    "params": {
      "spin_direction": "Z",
      "start_index": 15,
      "domain_size": 10,
      "base_state": 1,
      "flip_state": 2
    }
  }
}
```

**Parameters:**
- `spin_direction` - Quantization axis
- `start_index` - Where domain starts (1 to N)
- `domain_size` - How many sites to flip
- `base_state` - Background eigenstate
- `flip_state` - Domain eigenstate

**Example:**

**Localized excitation:**
```json
{
  "spin_direction": "Z",
  "start_index": 15,
  "domain_size": 10,
  "base_state": 1,
  "flip_state": 2
}
```
Creates: |↑↑...↑ ↓↓↓↓↓↓↓↓↓↓ ↑↑...↑⟩
         (sites 15-24 are down, rest are up)

**Use cases:**
- Localized spin flips
- Bubble dynamics
- Multiple domain walls

---

### Spin-Boson Prebuilt States

For spin-boson systems, the first site is always a BosonSite, followed by N_spins SpinSites.

**Pattern:**
```
[boson_level, spin_pattern...]
```

#### **1. Polarized (Spin-Boson)**

**Configuration:**
```json
{
  "system": {"type": "spinboson", "N_spins": 40, "nmax": 10},
  "state": {
    "type": "prebuilt",
    "name": "polarized",
    "params": {
      "boson_level": 0,
      "spin_direction": "Z",
      "spin_eigenstate": 1
    }
  }
}
```

**Creates:** |n⟩⊗|s⟩⊗|s⟩⊗...⊗|s⟩

**Parameters:**
- `boson_level` - Fock state (0 to nmax)
- `spin_direction` - Spin quantization axis
- `spin_eigenstate` - Which spin eigenstate

**Example:** Vacuum + all spins up
```json
{"boson_level": 0, "spin_direction": "Z", "spin_eigenstate": 1}
```

---

#### **2. Neel (Spin-Boson)**

**Configuration:**
```json
{
  "state": {
    "type": "prebuilt",
    "name": "neel",
    "params": {
      "boson_level": 5,
      "spin_direction": "Z",
      "even_state": 1,
      "odd_state": 2
    }
  }
}
```

**Creates:** |n⟩⊗|↑↓↑↓...⟩

**Example:** 5 bosons + Neel spin pattern

---

#### **3. Kink (Spin-Boson)**

**Configuration:**
```json
{
  "state": {
    "type": "prebuilt",
    "name": "kink",
    "params": {
      "boson_level": 0,
      "spin_direction": "Z",
      "position": 20,
      "left_state": 1,
      "right_state": 2
    }
  }
}
```

**Creates:** |n⟩⊗|↑↑...↑↓↓...↓⟩

---

#### **4. Domain (Spin-Boson)**

**Configuration:**
```json
{
  "state": {
    "type": "prebuilt",
    "name": "domain",
    "params": {
      "boson_level": 0,
      "spin_direction": "Z",
      "start_index": 15,
      "domain_size": 10,
      "base_state": 1,
      "flip_state": 2
    }
  }
}
```

**Creates:** |n⟩⊗|↑...↑↓↓↓...↓↑...↑⟩

---

## Custom States

Custom states allow site-by-site manual specification of the quantum state. Still produces **product states** (bond dimension 1).

### Spin-Only Custom States

**Configuration:**
```json
{
  "state": {
    "type": "custom",
    "spin_label": [
      ["Z", 1],
      ["Z", 2],
      ["X", 1],
      ["Y", 2],
      ["Z", 1],
      ...
    ]
  }
}
```

**Format:**
Each element is `[direction, eigenstate_index]`:
- `direction` - "X", "Y", or "Z"
- `eigenstate_index` - Which eigenstate (1, 2, ...)

**Must specify exactly N sites** (length must match system size)

**Example:**

For N=5:
```json
{
  "spin_label": [
    ["Z", 1],  # Site 1: |↑⟩_z
    ["Z", 2],  # Site 2: |↓⟩_z
    ["X", 1],  # Site 3: |+⟩_x
    ["Y", 1],  # Site 4: |+⟩_y
    ["Z", 1]   # Site 5: |↑⟩_z
  ]
}
```

Creates: |↑⟩_z ⊗ |↓⟩_z ⊗ |+⟩_x ⊗ |+⟩_y ⊗ |↑⟩_z

**Use cases:**
- Arbitrary product states
- Testing specific configurations
- Non-standard initial conditions

---

### Spin-Boson Custom States

**Configuration:**
```json
{
  "state": {
    "type": "custom",
    "boson_level": 3,
    "spin_label": [
      ["Z", 1],
      ["Z", 2],
      ["X", 1],
      ...
    ]
  }
}
```

**Parameters:**
- `boson_level` - Fock state number (0 to nmax)
- `spin_label` - Array of spin configurations (length = N_spins)

**Example:**

For N_spins=3, nmax=10:
```json
{
  "boson_level": 3,
  "spin_label": [
    ["Z", 1],
    ["X", 1],
    ["Y", 2]
  ]
}
```

Creates: |3⟩ ⊗ |↑⟩_z ⊗ |+⟩_x ⊗ |-⟩_y

---

## Random States

Random states have non-trivial entanglement (bond dimension > 1). Used as initial states for DMRG ground state search.

### Configuration

```json
{
  "state": {
    "type": "random",
    "params": {
      "bond_dim": 10
    }
  }
}
```

**Parameters:**
- `bond_dim` - Maximum bond dimension (χ)

### Construction

Random states are created with uniformly random tensor elements:

```julia
function random_state(sites, bond_dim, T=ComplexF64)
    N = length(sites)
    tensors = []
    
    # Left boundary: [1 × d × χ]
    push!(tensors, rand(T, 1, sites[1].dim, bond_dim))
    
    # Bulk: [χ × d × χ]
    for i in 2:N-1
        push!(tensors, rand(T, bond_dim, sites[i].dim, bond_dim))
    end
    
    # Right boundary: [χ × d × 1]
    push!(tensors, rand(T, bond_dim, sites[N].dim, 1))
    
    return MPS{T}(tensors)
end
```

**Notes:**
- Not normalized (normalized during canonicalization in algorithm)
- Highly entangled (good starting point for DMRG)
- Bond dimension uniform across chain

**Use cases:**
- Initial state for DMRG (ground state unknown)
- Avoiding symmetry traps
- Excited state calculations

---

## Internal Implementation

### Step-by-Step Construction Process

**Example: Building Neel State for N=4 spins**

**Step 1: Build Sites**
```julia
config = {"system": {"type": "spin", "N": 4, "S": 0.5}}
sites = _build_sites_from_config(config["system"])
# Returns: [SpinSite(0.5), SpinSite(0.5), SpinSite(0.5), SpinSite(0.5)]
```

**Step 2: Generate Pattern**
```julia
params = {"spin_direction": "Z", "even_state": 1, "odd_state": 2}
pattern = _get_label_neel(4, :Z, even_state=1, odd_state=2)
# Returns: [(:Z, 2), (:Z, 1), (:Z, 2), (:Z, 1)]
#           |↓⟩     |↑⟩     |↓⟩     |↑⟩
```

**Step 3: Create State Tensors**
```julia
tensors = []
for i in 1:4
    tensor = _state_tensor(sites[i], pattern[i])
    push!(tensors, tensor)
end

# tensor[1] = reshape([0; 1], 1, 2, 1)  # |↓⟩
# tensor[2] = reshape([1; 0], 1, 2, 1)  # |↑⟩
# tensor[3] = reshape([0; 1], 1, 2, 1)  # |↓⟩
# tensor[4] = reshape([1; 0], 1, 2, 1)  # |↑⟩
```

**Step 4: Assemble MPS**
```julia
mps = MPS{ComplexF64}(tensors)
# Bond dimensions: [1 × 2 × 1] - [1 × 2 × 1] - [1 × 2 × 1] - [1 × 2 × 1]
```

**Resulting state:** |↓↑↓↑⟩ (Neel pattern)

---

### Spin Operators: Mathematical Details

**Spin-1/2 operators:**

For S = 1/2, dimension d = 2, m = {+1/2, -1/2}:

**Sz (diagonal):**
```julia
Sz = Diagonal([0.5, -0.5])
   = [0.5   0  ]
     [0   -0.5]
```

**Ladder operators:**
```julia
S+ = [0  1]     # Raises spin
     [0  0]

S- = [0  0]     # Lowers spin
     [1  0]
```

**Cartesian operators:**
```julia
Sx = (S+ + S-)/2 = [0    0.5]
                   [0.5  0  ]

Sy = (S+ - S-)/(2i) = [0   -0.5i]
                      [0.5i  0  ]
```

**Eigenstates:**

Z-basis:
```julia
|↑⟩ = [1]  # Eigenvalue: +0.5
      [0]

|↓⟩ = [0]  # Eigenvalue: -0.5
      [1]
```

X-basis:
```julia
|+⟩ = [1/√2]   # Eigenvalue: +0.5
      [1/√2]

|-⟩ = [ 1/√2]  # Eigenvalue: -0.5
      [-1/√2]
```

**Spin-1 operators:**

For S = 1, dimension d = 3, m = {+1, 0, -1}:

```julia
Sz = [1   0   0]
     [0   0   0]
     [0   0  -1]

Sx = [0   1/√2    0  ]
     [1/√2  0   1/√2]
     [0   1/√2    0  ]
```

---

### Boson Operators: Mathematical Details

**For nmax = 2 (3 states: |0⟩, |1⟩, |2⟩):**

**Annihilation operator:**
```julia
a = [0  √1  0 ]
    [0   0  √2]
    [0   0  0 ]
```

**Creation operator:**
```julia
a† = [0   0   0]
     [√1  0   0]
     [0   √2  0]
```

**Number operator:**
```julia
b†b = [0  0  0]
      [0  1  0]
      [0  0  2]
```

**Fock states:**
```julia
|0⟩ = [1]  # Vacuum
      [0]
      [0]

|1⟩ = [0]  # One boson
      [1]
      [0]

|2⟩ = [0]  # Two bosons
      [0]
      [1]
```

---

### Performance Considerations

**Memory scaling for product states:**
```
MPS memory ~ N × d × sizeof(T)
```

For N=100 spins (d=2), ComplexF64:
```
Memory ~ 100 × 2 × 16 bytes = 3.2 KB
```

**Memory scaling for random states:**
```
MPS memory ~ N × χ² × d × sizeof(T)
```

For N=100, χ=20, d=2, ComplexF64:
```
Memory ~ 100 × 400 × 2 × 16 bytes = 1.3 MB
```

**Construction time:**

- **Product states**: O(N × d²) - dominated by eigenvector reshaping
- **Random states**: O(N × χ² × d) - dominated by random number generation

For typical parameters:
- Product state: <1 ms
- Random state (χ=50): ~10 ms

---

## Extension Guide

### Adding New Prebuilt States

**Step 1: Create pattern generator**

Add to `statebuilder.jl`:

```julia
function _get_label_my_pattern(N::Int, direction::Symbol; params...)
    pattern = []
    for i in 1:N
        # Your logic here
        eigenstate = ... # compute based on i and params
        push!(pattern, (direction, eigenstate))
    end
    return pattern
end
```

**Step 2: Add to builder function**

In `_build_spin_prebuilt_state()`:

```julia
elseif name == "my_pattern"
    pattern = _get_label_my_pattern(N, spin_direction, 
                                   param1=params["param1"],
                                   param2=params["param2"])
```

**Step 3: Document in this file**

Add example configuration and physics description.

---

### Example: Adding "Stripe" State

**Physics:** Periodic pattern with period p

```julia
function _get_label_stripe(N::Int, direction::Symbol; period::Int=2, 
                          states::Vector{Int}=[1,2])
    pattern = []
    for i in 1:N
        idx = mod1(i, period)
        push!(pattern, (direction, states[idx]))
    end
    return pattern
end
```

**Usage:**
```json
{
  "state": {
    "type": "prebuilt",
    "name": "stripe",
    "params": {
      "spin_direction": "Z",
      "period": 3,
      "states": [1, 2, 1]
    }
  }
}
```

Creates: |↑↓↑ ↑↓↑ ↑↓↑...⟩

---

## Summary

TNCodebase's state building system provides:

**Flexibility:**
- Prebuilt templates for common patterns
- Custom site-by-site specification
- Random states for variational methods

**Efficiency:**
- Precomputed eigenspectra (no runtime diagonalization)
- Product states have minimal bond dimension
- Efficient tensor reshaping

**Type Safety:**
- Parametric types throughout
- Type propagation from sites to MPS
- Supports Float64 and ComplexF64

**Extensibility:**
- Easy to add new prebuilt patterns
- Custom states for arbitrary product states
- Modular site/pattern/MPS separation

**Best practices:**
- Use prebuilt states for standard initial conditions
- Use custom states for testing specific configurations
- Use random states for DMRG ground state search
- Choose appropriate quantization axis for physics

For working examples, see:
- `examples/states/prebuilt/` - Template usage
- `examples/states/custom/` - Site-by-site specification
- `examples/dmrg/` - Random state initialization

For implementation details, see:
- `src/Core/site.jl` - Site types and operators
- `src/Builders/mpsbuilder.jl` - MPS construction
- `src/Builders/statebuilder.jl` - Pattern generators and config parsing
