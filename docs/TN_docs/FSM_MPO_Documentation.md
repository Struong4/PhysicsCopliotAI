# Finite State Machine-Based MPO Construction

## Technical Documentation

This document provides a detailed technical description of how Matrix Product Operators (MPOs) are constructed using Finite State Machines (FSMs) in TNCodebase. The implementation is split across two core modules: `fsm.jl` (FSM construction) and `mpobuilder.jl` (MPO tensor assembly).

---

## Table of Contents

1. [Overview](#overview)
2. [Channel Types](#channel-types)
3. [FSM Transition Building](#fsm-transition-building)
4. [Power-Law Decomposition](#power-law-decomposition)
5. [FSM Construction](#fsm-construction)
6. [MPO Assembly](#mpo-assembly)
7. [Mathematical Formulation](#mathematical-formulation)

---

## Overview

### Motivation

Many-body Hamiltonians can be efficiently represented as Matrix Product Operators (MPOs), where the bond dimension χ controls both the computational cost and the complexity of interactions that can be represented. The FSM-based approach provides a systematic way to construct MPOs for arbitrary Hamiltonians while optimizing the bond dimension.

### Architecture

The construction process follows this pipeline:

```
Channels → FSM Transitions → FSM Path → MPO Tensors
```

1. **Channels** encode physical interactions (couplings, fields)
2. **Transitions** define state-to-state paths with operators
3. **FSM Path** aggregates all transitions with bond dimension χ
4. **MPO Tensors** are assembled from the FSM representation

---

## Channel Types

### Type Hierarchy

```julia
abstract type Channel end
abstract type Spin  <: Channel end
abstract type Boson <: Channel end
```

All interaction terms are encoded as channels, which are then compiled into FSM transitions.

### 1. FiniteRangeCoupling

**Mathematical Form:**
```
H = w · Σᵢ Aᵢ Bᵢ₊ₐₓ
```

**Structure:**
```julia
struct FiniteRangeCoupling <: Spin
    op1::Symbol      # Operator A
    op2::Symbol      # Operator B
    dx::Int          # Distance Δx
    weight::Float64  # Coupling strength w
end
```

**Example:** Nearest-neighbor Ising
```
FiniteRangeCoupling(:Z, :Z, 1, -1.0)  # -Σᵢ Zᵢ Zᵢ₊₁
```

### 2. ExpChannelCoupling

**Mathematical Form:**
```
H = a · Σᵢ<ⱼ Aᵢ Bⱼ · λʳ    where r = j - i
```

**Structure:**
```julia
struct ExpChannelCoupling <: Spin
    op1::Symbol        # Operator A
    op2::Symbol        # Operator B
    amplitude::Float64 # Prefactor a
    decay::Float64     # Base λ
end
```

**Example:** Exponentially decaying interaction
```
ExpChannelCoupling(:Z, :Z, 1.0, 0.9)  # Σᵢ<ⱼ Zᵢ Zⱼ · (0.9)ʳ
```

### 3. PowerLawCoupling

**Mathematical Form:**
```
H = J · Σᵢ<ⱼ Aᵢ Bⱼ / |i-j|^α
```

**Structure:**
```julia
struct PowerLawCoupling <: Spin
    op1::Symbol     # Operator A
    op2::Symbol     # Operator B
    J::Float64      # Coupling strength J
    alpha::Float64  # Power-law exponent α
    bondH::Int      # Number of exponentials K
    N::Int          # System size
end
```

**Implementation:** Uses sum-of-exponentials approximation:
```
1/r^α ≈ Σₖ₌₁ᴷ νₖ λₖʳ
```

### 4. Field

**Mathematical Form:**
```
H = w · Σᵢ Aᵢ
```

**Structure:**
```julia
struct Field <: Spin
    op::Symbol       # Operator A
    weight::Float64  # Field strength w
end
```

**Example:** Transverse field
```
Field(:X, 0.5)  # 0.5 · Σᵢ Xᵢ
```

### 5. BosonOnly

**Mathematical Form:**
```
H = w · Bₒₚ
```

**Structure:**
```julia
struct BosonOnly <: Boson
    op::Symbol       # Boson operator
    weight::Float64  # Strength w
end
```

**Example:** Boson energy
```
BosonOnly(:Bn, 1.0)  # ω · b†b (where Bn = b†b)
```

### 6. SpinBosonInteraction

**Mathematical Form:**
```
H = w_b · Bₒₚ ⊗ (spin channels)
```

**Structure:**
```julia
struct SpinBosonInteraction <: Boson
    spin_channel::Vector{<:Spin}  # Spin interaction terms
    boson_op::Symbol               # Boson operator
    weight_boson::Float64          # Boson coupling w_b
end
```

**Example:** Tavis-Cummings absorption
```
SpinBosonInteraction(
    [Field(:Sp, 1.0)],  # Σᵢ σ⁺ᵢ
    :a,                 # Boson annihilation
    0.2                 # g
)
# Creates: 0.2 · a ⊗ (Σᵢ σ⁺ᵢ)
```

---

## FSM Transition Building

### Transition Format

Each transition is a 4-tuple:
```julia
(source_state, target_state, operator, weight)
```

Where:
- `source_state`: Integer index (1 = initial idle, 0 = placeholder for final)
- `target_state`: Integer index (0 = placeholder for final)
- `operator`: Symbol representing physical operator
- `weight`: Scalar coefficient

### FSM Diagrams

#### FiniteRangeCoupling FSM

For `FiniteRangeCoupling(:A, :B, dx=3, w=J)`:

```
State Transitions:
    [1] ──A──> [ns+1] ──I──> [ns+2] ──I──> [ns+3] ──J·B──> [final]
    
Site-by-site action:
    Site i:   emit A, transition to auxiliary state
    Site i+1: emit I, stay in chain
    Site i+2: emit I, stay in chain
    Site i+3: emit J·B, return to final state
```

**Generated transitions:**
```julia
(ns+1, 1,    :A, 1.0)    # Idle → state 1: emit A
(ns+2, ns+1, :I, 1.0)    # State 1 → 2: emit I
(ns+3, ns+2, :I, 1.0)    # State 2 → 3: emit I
(0,    ns+3, :B, J)      # State 3 → final: emit J·B
```

#### ExpChannelCoupling FSM

For `ExpChannelCoupling(:A, :B, amplitude=a, decay=λ)`:

```
State Transitions:
    [1] ──A──> [ns+1] ⟲(I,λ) ──a·λ·B──> [final]
    
Site-by-site action:
    Site i:   emit A, enter decay loop
    Site i+r: emit I, accumulate factor λʳ⁻¹
    Site j:   emit a·λ·B, exit to final state
    
The self-loop multiplies by λ at each step, creating exponential decay.
```

**Generated transitions:**
```julia
(ns+1, 1,    :A, 1.0)      # Idle → loop: emit A
(ns+1, ns+1, :I, λ)        # Loop: emit I, multiply by λ
(0,    ns+1, :B, a·λ)      # Loop → final: emit a·λ·B
```

**Accumulated weight after r steps:**
```
Site i emits A
Site i+1: I contributes λ¹
Site i+2: I contributes λ²
...
Site i+r: B contributes a·λ·λʳ⁻¹ = a·λʳ

Total: A ⊗ I^(r-1) ⊗ (a·λʳ)B
```

#### PowerLawCoupling FSM

For `PowerLawCoupling(:A, :B, J, α, K, N)`:

First decomposes: `1/r^α ≈ Σₖ νₖ λₖʳ`

Then creates K parallel exponential paths:

```
State Transitions (K paths):
    [1] ──A──> [ns+1] ⟲(I,λ₁) ──J·ν₁·λ₁·B──> [final]
    [1] ──A──> [ns+2] ⟲(I,λ₂) ──J·ν₂·λ₂·B──> [final]
    ...
    [1] ──A──> [ns+K] ⟲(I,λₖ) ──J·νₖ·λₖ·B──> [final]
```

**Generated transitions:**
```julia
# For each k = 1 to K:
(ns+k, 1,    :A, 1.0)          # Idle → loop k: emit A
(ns+k, ns+k, :I, λₖ)           # Loop k: self-loop with λₖ
(0,    ns+k, :B, J·νₖ·λₖ)      # Loop k → final: emit weighted B
```

**Bond dimension:** χ ∝ K instead of χ ∝ N

#### Field FSM

For `Field(:A, w)`:

```
State Transitions:
    [1] ──w·A──> [final]
    
Single-site operator applied at every site.
```

**Generated transitions:**
```julia
(0, 1, :A, w)    # Idle → final: emit w·A
```

**No auxiliary states needed** (ns unchanged).

---

## Power-Law Decomposition

### Algorithm: `_power_law_to_exp(α, K, N)`

**Goal:** Approximate `f(r) = 1/r^α` for `r ∈ [1, N]` using K exponentials:
```
1/r^α ≈ Σₖ₌₁ᴷ νₖ λₖʳ
```

### Mathematical Procedure

**Step 1: Construct Target Vector**
```julia
F[k] = 1/k^α    for k = 1, ..., N
```

**Step 2: Form Shifted Matrix**
```julia
M[i,j] = F[i+j-1]    for i = 1, ..., N-K+1, j = 1, ..., K
```

This creates a matrix where each column is `F` shifted by `j-1`.

**Step 3: QR Decomposition**
```julia
M = Q R
```

Extract `Q₁` (first N-K rows) and `Q₂` (rows 2 to N-K+1):
```julia
Q₁ = Q[1:N-K, 1:K]
Q₂ = Q[2:N-K+1, 1:K]
```

**Step 4: Eigenvalue Problem**
```julia
V = pinv(Q₁) * Q₂
λ = eigvals(V)
```

The eigenvalues `λ` are the exponential bases.

**Step 5: Least-Squares for Coefficients**

Construct matrix of exponential values:
```julia
Λ[k,j] = λⱼᵏ    for k = 1, ..., N, j = 1, ..., K
```

Solve for coefficients:
```julia
ν = Λ \ F
```

This minimizes `||Λ·ν - F||₂`.

### Result

Returns `(ν, λ)` where:
- `ν`: Vector of length K (coefficients)
- `λ`: Vector of length K (exponential bases)

Such that:
```
1/r^α ≈ Σₖ₌₁ᴷ νₖ λₖʳ
```

### Accuracy

The approximation quality depends on K:
- Small K (5-10): Fast but less accurate
- Large K (15-20): More accurate but larger bond dimension

**Typical error:** ~1-5% for K=10 over range [1, N=100]

---

## FSM Construction

### Function: `build_FSM(channels)`

Aggregates multiple channels into a single FSM.

### Algorithm

**Input:** Vector of channels
**Output:** `FSMPath` struct with bond dimension χ and transitions

**Pseudocode:**
```
1. Initialize: ns = 1 (current number of states)
2. Add base transitions:
   - (1, 1, I, 1.0)  # Initial idle state self-loop
   - (0, 0, I, 1.0)  # Final idle state self-loop (placeholder)
3. For each channel:
   - Call _build_path(ns, channel, transitions)
   - Update ns to new state count
   - Append new transitions to list
4. Relabel: Replace placeholder 0 with final state index (ns+1)
5. Return FSMPath(χ=ns+1, transitions)
```

### State Indexing Convention

- **State 1:** Initial idle state (always present)
- **States 2 to ns:** Auxiliary states from channels
- **State ns+1:** Final idle state
- **Placeholder 0:** Used during construction, replaced with ns+1

### Example: Two Channels

**Channels:**
```julia
channels = [
    FiniteRangeCoupling(:Z, :Z, 1, -1.0),  # Nearest-neighbor
    Field(:X, 0.5)                          # Transverse field
]
```

**FSM construction:**

1. **Base transitions:**
```
(1, 1, I, 1.0)
(0, 0, I, 1.0)
```

2. **After FiniteRangeCoupling (ns=1 → ns=2):**
```
(2, 1, Z, 1.0)     # Emit Z, go to state 2
(0, 2, Z, -1.0)    # From state 2, emit -Z, go to final
```

3. **After Field (ns=2, unchanged):**
```
(0, 1, X, 0.5)     # From idle, emit 0.5X, go to final
```

4. **Relabel (final = 3):**
```
(1, 1, I, 1.0)     # Idle self-loop
(3, 3, I, 1.0)     # Final self-loop
(2, 1, Z, 1.0)     # Coupling: Z emission
(3, 2, Z, -1.0)    # Coupling: receive Z
(3, 1, X, 0.5)     # Field: direct X term
```

**Bond dimension:** χ = 3

### Spin-Boson FSM

For `SpinBosonInteraction` channels:

1. Build spin FSM from `spin_channel` vector
2. Attach boson operator to final transition
3. Combine with other boson channels

**Example:**
```julia
channels = [
    SpinBosonInteraction(
        [Field(:Sp, 1.0)],
        :a,
        0.2
    ),
    BosonOnly(:Bn, 1.0)
]
```

**Process:**
1. Build spin FSM for `Field(:Sp, 1.0)`: creates transition (0, 1, Sp, 1.0)
2. Attach boson operator: (0, ns, a, 0.2)
3. Add boson-only term: (0, 1, Bn, 1.0)

---

## MPO Assembly

### Function: `build_mpo(fsm, N, d, T)`

Constructs N-site MPO tensors from FSM transitions.

### MPO Tensor Structure

An MPO is a sequence of 4-index tensors:
```
W[i] has indices: [χₗₑfₜ, χᵣᵢgₕₜ, d_out, d_in]
```

Where:
- `χₗₑfₜ, χᵣᵢgₕₜ`: Virtual bond indices (FSM states)
- `d_out, d_in`: Physical indices (Hilbert space dimensions)

### Construction Algorithm

**Step 1: Build Bulk Tensor**

Initialize zero tensor:
```julia
bulk = zeros(T, χ, χ, d, d)
```

Fill from FSM transitions:
```julia
for (row, col, opname, w) in fsm.transitions
    op_mat = phys_ops[opname]  # Get physical operator matrix
    bulk[row, col, :, :] += w * op_mat
end
```

**Structure:**
```
bulk[α, β, σ', σ] = Σ_transitions w · ⟨σ'|Ô|σ⟩ · δ(transition: α→β with op Ô)
```

**Step 2: Extract Boundary Tensors**

**Left edge (L):**
```julia
L = reshape(bulk[χ, :, :, :], (1, χ, d, d))
```

Selects only transitions **from** the final state (χ).

**Right edge (R):**
```julia
R = reshape(bulk[:, 1, :, :], (χ, 1, d, d))
```

Selects only transitions **to** the initial state (1).

**Step 3: Assemble MPO**
```julia
tensors = [L, bulk, bulk, ..., bulk, R]
         \_/  \___________________/  \_/
         site 1    sites 2 to N-1    site N
```

Total: N tensors

### Why This Works

The FSM encodes the Hamiltonian as a sum of operator strings:
```
H = Σ_paths w_path · (O₁ ⊗ O₂ ⊗ ... ⊗ Oₙ)
```

Each path through the FSM contributes one such string:
- **State α → β:** Virtual bond carries "partial string"
- **Operator Ô:** Acts on physical space
- **Weight w:** Contribution amplitude

The MPO contracts as:
```
⟨σ'₁...σ'ₙ|H|σ₁...σₙ⟩ = L[1,α₁,σ'₁,σ₁] · W[α₁,α₂,σ'₂,σ₂] · ... · R[αₙ₋₁,1,σ'ₙ,σₙ]
```

Summing over internal indices {α} sums over all FSM paths.

### Example: Nearest-Neighbor Ising

**Hamiltonian:**
```
H = -Σᵢ Zᵢ Zᵢ₊₁ + 0.5 Σᵢ Xᵢ
```

**FSM (χ=3):**
```
(1, 1, I,  1.0)
(2, 1, Z,  1.0)
(3, 2, Z, -1.0)
(3, 1, X,  0.5)
(3, 3, I,  1.0)
```

**Bulk tensor:**
```
W[1,1,:,:] = I
W[1,2,:,:] = Z
W[1,3,:,:] = 0.5·X
W[2,3,:,:] = -Z
W[3,3,:,:] = I
```

In matrix form (suppressing physical indices):
```
     [  I    Z   0.5X ]
W =  [  0    0    -Z  ]
     [  0    0     I  ]
```

**Left edge:**
```
L = [ 0  0  I ]  (selects row 3)
```

**Right edge:**
```
R = [ I ]  (selects column 1)
    [ 0 ]
    [ 0 ]
```

**MPO contraction:**
```
Site 1: L·W = [0, 0, I] · W = [0, 0, I]
Site i: W (unchanged)
Site N: W·R selects column 1
```

The path `1→1→...→3→2→3→...→1` gives the Ising term:
```
I⊗...⊗I⊗Z⊗I⊗...⊗I⊗(-Z)⊗I⊗...⊗I = -Zᵢ⊗Zᵢ₊₁
```

The path `1→3→...→1` gives the field term at each site:
```
0.5·X at every site
```

### Spin-Boson MPO

For heterogeneous systems (1 boson + N spins):

**Differences:**
1. **Left tensor** has boson dimension:
```julia
L = zeros(T, 1, χ-1, d_boson, d_boson)
```

2. **Bulk tensors** have spin dimension:
```julia
bulk = zeros(T, χ-1, χ-1, d_spin, d_spin)
```

3. **FSM transitions** distinguish boson vs spin operators:
```julia
for (row, col, opname, w) in fsm.transitions
    if row == χ  # Final state index
        L[1, col, :, :] += w * phys_ops[opname]  # Boson site
    else
        bulk[row, col, :, :] += w * phys_ops[opname]  # Spin sites
    end
end
```

**Bond dimension:** χ_spin = χ_total - 1 (boson site absorbs one index)

---

## Mathematical Formulation

### General Hamiltonian Representation

Any Hamiltonian can be written as:
```
H = Σₚ wₚ · Oₚ

where Oₚ = Oₚ₁ ⊗ Oₚ₂ ⊗ ... ⊗ Oₚₙ
```

### MPO as Compressed Sum

The MPO tensor network provides an efficient representation:
```
H[σ'₁...σ'ₙ, σ₁...σₙ] = Σ_{α₁...αₙ₋₁} L[1,α₁,σ'₁,σ₁] ∏ᵢ₌₂ⁿ⁻¹ W[αᵢ₋₁,αᵢ,σ'ᵢ,σᵢ] R[αₙ₋₁,1,σ'ₙ,σₙ]
```

**Compression:** Instead of storing all dⁿ×dⁿ matrix elements, store:
- O(N·χ²·d²) tensor elements
- χ = bond dimension (typically χ << dⁿ/²)

### Bond Dimension Scaling

| Interaction Type | Naive χ | FSM χ | Savings |
|------------------|---------|-------|---------|
| Nearest-neighbor | 3 | 3 | None |
| Finite-range (range R) | R+2 | R+2 | None |
| Exponential decay | N | 2 | O(N) |
| Power-law (K exponentials) | N | K+2 | O(N/K) |

**Key insight:** Long-range interactions decompose into few exponentials, dramatically reducing χ.

### Operator String Encoding

Each path `1 → α₁ → α₂ → ... → αₘ → final` encodes an operator string:
```
w · (O₁ ⊗ O₂ ⊗ ... ⊗ Oₙ)
```

Where:
- Transition `αᵢ → αᵢ₊₁` at site j emits operator `Oⱼ`
- Final transition contributes weight `w`
- Identity operators inserted automatically via self-loops

### Physical Locality Constraint

The FSM formalism guarantees:
```
[H, Locality] = 0 (up to exponential/power-law tails)
```

All interactions respect:
1. Translational invariance (bulk tensor repeated)
2. Causality (left/right structure)
3. Hermiticity (if operator matrices are Hermitian)

---

## Implementation Notes

### Operator Factory

Physical operators are generated via `spin_ops(d)` and `boson_ops(nmax)`:

**Spin operators (d=2):**
```julia
:I  → [ 1  0 ]    Identity
      [ 0  1 ]

:X  → [ 0  1 ]    Pauli X
      [ 1  0 ]

:Y  → [ 0 -i ]    Pauli Y
      [ i  0 ]

:Z  → [ 1  0 ]    Pauli Z
      [ 0 -1 ]

:Sp → [ 0  1 ]    Raising operator
      [ 0  0 ]

:Sm → [ 0  0 ]    Lowering operator
      [ 1  0 ]
```

**Boson operators (nmax=N):**
```julia
:Ib    → I_{(N+1)×(N+1)}              Identity
:a     → Annihilation (lower diagonal)
:adag  → Creation (upper diagonal)
:Bn    → Number operator (diagonal: 0,1,2,...,N)
```

### Efficiency Considerations

1. **Memory:** O(N·χ²·d²) for MPO storage
2. **Construction time:** O(K_channels · χ) for FSM + O(χ²·d²) for tensor filling
3. **Contraction cost:** O(χ³·d³) per site during MPS evolution

### Extensibility

Adding new channel types requires:
1. Define new struct inheriting from `Spin` or `Boson`
2. Implement `_build_path(ns, channel, transitions)` method
3. Channel automatically integrates into FSM/MPO pipeline

---

## References

### Theoretical Background

1. **MPO formalism:** Schollwöck, Ann. Phys. **326**, 96 (2011)
2. **FSM for Hamiltonians:** Crosswhite et al., Phys. Rev. A **78**, 012356 (2008)

### Code Implementation

- `src/Core/fsm.jl`: Channel types, FSM construction, power-law decomposition
- `src/Builders/mpobuilder.jl`: MPO tensor assembly from FSM

---

## Summary

The FSM-based MPO construction provides:

1. **Modularity:** Hamiltonians built from composable channels
2. **Efficiency:** Optimal bond dimension via FSM minimization
3. **Scalability:** Long-range interactions represented with O(log N) bond dimension
4. **Generality:** Unified framework for spin, boson, and heterogeneous systems

The key innovation is treating Hamiltonian construction as a **graph problem** (FSM states and transitions) rather than directly manipulating tensor indices, enabling systematic optimization and clean separation between physics specification (channels) and numerical implementation (MPO tensors).
