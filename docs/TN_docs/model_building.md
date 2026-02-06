# Model Building Guide

## Overview

TNCodebase provides a flexible, extensible framework for constructing quantum many-body Hamiltonians as Matrix Product Operators (MPOs). The system is designed around two core principles:

1. **Config-driven specification** - Models are defined entirely through JSON configuration files
2. **Channel-based construction** - Hamiltonians are built from composable interaction primitives

This design separates the physics (what interactions exist) from the implementation (how to build efficient MPO representations), enabling rapid experimentation while maintaining computational efficiency.

---

## Architecture

### Construction Flow

```
JSON Config → Channel Parser → FSM Builder → MPO Constructor → MPO{T}
```

**Step 1: Configuration Parsing**
- User specifies model in JSON (prebuilt template or custom channels)
- `parse_spin_channels()` or `parse_spinboson_channels()` converts to channel objects

**Step 2: FSM Construction**
- `build_FSM()` creates finite state machine representation
- Handles finite-range, exponential decay, and power-law couplings
- Optimizes MPO bond dimension

**Step 3: MPO Building**
- `build_mpo()` constructs MPO tensors from FSM
- Generates boundary and bulk tensors
- Returns `MPO{T}` ready for simulation

### Key Design Features

**Composability:**
- Each channel represents one physical interaction
- Channels combine additively to form complex Hamiltonians
- Easy to add/remove terms for systematic studies

**Efficiency:**
- Finite state machines minimize MPO bond dimension
- Power-law interactions use sum-of-exponentials decomposition
- Exponential decay channels use analytical continuation

**Type Safety:**
- Parametric types `MPO{T}` where `T <: Number`
- Supports `Float64`, `ComplexF64`, etc.
- Type promotion handled automatically

---

## Prebuilt Models

Prebuilt models are template Hamiltonians with commonly used forms. They provide a quick way to specify standard models without dealing with channel construction.

### Available Templates

#### **Transverse Field Ising Model (TFIM)**

**Hamiltonian:**
```
H = J Σᵢ σᵃᵢσᵃᵢ₊₁ + h Σᵢ σᵇᵢ
```

**Configuration:**
```json
{
  "model": {
    "name": "transverse_field_ising",
    "params": {
      "N": 40,
      "J": -1.0,
      "h": 0.5,
      "coupling_dir": "Z",
      "field_dir": "X",
      "dtype": "Float64"
    }
  }
}
```

**Parameters:**
- `N` - System size (number of sites)
- `J` - Coupling strength (negative = ferromagnetic)
- `h` - Transverse field strength
- `coupling_dir` - Coupling operator: "X", "Y", or "Z"
- `field_dir` - Field operator: "X", "Y", or "Z"
- `dtype` - Data type: "Float64" or "ComplexF64"

**Use cases:**
- Quantum phase transitions (critical point at h/J ≈ 1)
- Ground state benchmarking
- Quench dynamics

---

#### **Heisenberg Chain**

**Hamiltonian:**
```
H = Jₓ Σᵢ σˣᵢσˣᵢ₊₁ + Jᵧ Σᵢ σʸᵢσʸᵢ₊₁ + Jᵧ Σᵢ σᶻᵢσᶻᵢ₊₁ + hₓ Σᵢ σˣᵢ + hᵧ Σᵢ σʸᵢ + hᵧ Σᵢ σᶻᵢ
```

**Configuration:**
```json
{
  "model": {
    "name": "heisenberg",
    "params": {
      "N": 40,
      "Jx": 1.0,
      "Jy": 1.0,
      "Jz": 1.0,
      "hx": 0.0,
      "hy": 0.0,
      "hz": 0.0,
      "dtype": "Float64"
    }
  }
}
```

**Parameters:**
- `Jx`, `Jy`, `Jz` - Coupling strengths in each direction
- `hx`, `hy`, `hz` - Magnetic field components (X, Y, Z directions)

**Special cases:**
- `Jx = Jy = Jz` - Isotropic (SU(2) symmetric)
- `Jx = Jy ≠ Jz` - XXZ model
- `Jz ≠ 0, Jx = Jy = 0` - Ising model
- Set `hx = hy = 0, hz ≠ 0` for longitudinal field only

---

#### **Long-Range Ising Model**

**Hamiltonian:**
```
H = J Σᵢ<ⱼ σᶻᵢσᶻⱼ/|i-j|^α + h Σᵢ σˣᵢ
```

**Configuration:**
```json
{
  "model": {
    "name": "long_range_ising",
    "params": {
      "N": 40,
      "J": 1.0,
      "alpha": 1.5,
      "h": 0.5,
      "coupling_dir": "Z",
      "field_dir": "X",
      "n_exp": 10,
      "dtype": "Float64"
    }
  }
}
```

**Parameters:**
- `alpha` - Power-law exponent (α > 0)
- `n_exp` - Number of exponentials in decomposition (higher = more accurate)

**Technical note:** Uses sum-of-exponentials decomposition (see FSM section below)

---

#### **Spin-Boson Model: Ising-Dicke**

**Hamiltonian:**
```
H = ω b†b + J Σᵢ σᶻᵢσᶻᵢ₊₁ + h Σᵢ σᶻᵢ + g(a + a†)Σᵢ σˣᵢ
```

Nearest-neighbor Ising model coupled to a bosonic mode via Dicke-type coupling.

**Configuration:**
```json
{
  "model": {
    "name": "ising_dickie",
    "params": {
      "N_spins": 40,
      "nmax": 10,
      "J": 1.0,
      "h": 0.0,
      "omega": 1.0,
      "g": 0.1,
      "spin_coupling_dir": "Z",
      "spin_field_dir": "Z",
      "boson_coupling_dir": "X",
      "dtype": "Float64"
    }
  }
}
```

**Parameters:**
- `N_spins` - Number of spin sites
- `nmax` - Bosonic Hilbert space truncation (0 to nmax bosons)
- `J` - Nearest-neighbor spin coupling strength
- `h` - Spin field strength
- `omega` - Boson frequency (ω)
- `g` - Spin-boson coupling strength
- `spin_coupling_dir` - Spin-spin coupling direction ("X", "Y", or "Z")
- `spin_field_dir` - Spin field direction ("X", "Y", or "Z")
- `boson_coupling_dir` - Which spin component couples to boson ("X", "Y", or "Z")

**Implementation details:**
Internally constructs three `SpinBosonInteraction` channels:
1. Spin-only part: `FiniteRangeCoupling` + `Field` with `boson_op: "Ib"` (identity)
2. Spin-boson annihilation: `Field` × `g` with `boson_op: "a"`
3. Spin-boson creation: `Field` × `g` with `boson_op: "adag"`
Plus one `BosonOnly` channel for boson energy.

**Use cases:**
- Cavity QED with short-range spin interactions
- Phonon-coupled nearest-neighbor spin chains
- Dicke model physics

---

#### **Spin-Boson Model: Long-Range Ising-Dicke**

**Hamiltonian:**
```
H = ω b†b + J Σᵢ<ⱼ σᶻᵢσᶻⱼ/|i-j|^α + h Σᵢ σᶻᵢ + g(a + a†)Σᵢ σˣᵢ
```

Long-range power-law Ising model coupled to a bosonic mode.

**Configuration:**
```json
{
  "model": {
    "name": "long_range_ising_dickie",
    "params": {
      "N_spins": 40,
      "nmax": 10,
      "J": 1.0,
      "alpha": 1.5,
      "n_exp": 10,
      "h": 0.0,
      "omega": 1.0,
      "g": 0.1,
      "spin_coupling_dir": "Z",
      "spin_field_dir": "Z",
      "boson_coupling_dir": "X",
      "dtype": "Float64"
    }
  }
}
```

**Parameters:**
- `alpha` - Power-law exponent for spin-spin interaction
- `n_exp` - Number of exponentials for power-law decomposition
- All other parameters same as `ising_dickie`

**Implementation details:**
Similar to `ising_dickie` but uses `PowerLawCoupling` instead of `FiniteRangeCoupling` for spin-spin interactions.

**Use cases:**
- Trapped ion systems (long-range Coulomb interactions + phonon mode)
- Rydberg atoms in cavity
- Long-range spin models with dissipation

---

## Custom Models via Channels

Custom models are built from interaction channels - primitive building blocks that represent specific types of couplings.

### Channel Types

#### **1. FiniteRangeCoupling**

**Physics:** Nearest-neighbor or short-range two-site interactions

**Hamiltonian contribution:**
```
H += strength × Σᵢ op1ᵢ ⊗ op2ᵢ₊ᵣ
```

**Configuration:**
```json
{
  "type": "FiniteRangeCoupling",
  "op1": "Z",
  "op2": "Z",
  "range": 1,
  "strength": -1.0
}
```

**Parameters:**
- `op1`, `op2` - Operators: "X", "Y", "Z", "Plus", "Minus"
- `range` - Interaction range (1 = nearest neighbor, 2 = next-nearest, etc.)
- `strength` - Coupling constant

**Example:** Nearest-neighbor Ising: `op1="Z"`, `op2="Z"`, `range=1`, `strength=-1.0`

---

#### **2. ExpChannelCoupling**

**Physics:** Exponentially decaying interactions

**Hamiltonian contribution:**
```
H += amplitude × Σᵢ<ⱼ op1ᵢ ⊗ op2ⱼ × decay^|i-j|
```

**Configuration:**
```json
{
  "type": "ExpChannelCoupling",
  "op1": "Z",
  "op2": "Z",
  "amplitude": 1.0,
  "decay": 0.9
}
```

**Parameters:**
- `op1`, `op2` - Operators: "X", "Y", "Z", "Plus", "Minus"
- `amplitude` - Overall coupling strength
- `decay` - Exponential decay parameter (0 < decay < 1)

**Use cases:**
- Screened interactions
- Effective field theories
- Internal use in power-law decomposition

**Example:** `amplitude=1.0, decay=0.9` gives interaction `~0.9^r` where r is distance

---

#### **3. PowerLawCoupling**

**Physics:** Algebraic decay interactions

**Hamiltonian contribution:**
```
H += strength × Σᵢ<ⱼ op1ᵢ ⊗ op2ⱼ / |i-j|^α
```

**Configuration:**
```json
{
  "type": "PowerLawCoupling",
  "op1": "Z",
  "op2": "Z",
  "strength": 1.0,
  "alpha": 1.5,
  "n_exp": 10,
  "N": 40
}
```

**Parameters:**
- `op1`, `op2` - Operators: "X", "Y", "Z", "Plus", "Minus"
- `strength` - Overall coupling constant
- `alpha` - Power-law exponent (α > 0)
- `n_exp` - Number of exponentials for decomposition (typically 5-15)
- `N` - System size (required for decomposition range)

**Technical details:** See FSM section for decomposition method

**Typical values:**
- `n_exp = 5-10`: Good for α ~ 1-2, N ~ 50-100
- `n_exp = 10-15`: Better accuracy or larger systems
- Higher `n_exp` = better accuracy but larger MPO bond dimension

---

#### **4. Field**

**Physics:** Single-site terms

**Hamiltonian contribution:**
```
H += strength × Σᵢ opᵢ
```

**Configuration:**
```json
{
  "type": "Field",
  "op": "X",
  "strength": 0.5
}
```

**Example:** Transverse field in Ising model

---

#### **5. BosonOnly**

**Physics:** Pure bosonic operator term

**Hamiltonian contribution:**
```
H += strength × op
```

**Configuration:**
```json
{
  "type": "BosonOnly",
  "op": "Bn",
  "strength": 1.0
}
```

**Parameters:**
- `op` - Boson operator symbol: "Bn" (number operator b†b), "Ib" (identity), etc.
- `strength` - Coefficient (typically boson frequency ω for number operator)

**Common usage:**
```json
{
  "type": "BosonOnly",
  "op": "Bn",
  "strength": 1.0
}
```
Creates: `ω b†b` (boson energy with frequency ω=1.0)

**Use in:** Spin-boson models where boson mode has its own energy

**Note:** This term acts only on the bosonic degree of freedom. For spin-boson models, you need at least one `BosonOnly` channel and multiple `SpinBosonInteraction` channels to define the full Hamiltonian.

---

#### **6. SpinBosonInteraction**

**Physics:** Coupling between spin channels and bosonic operators

**Structure:** Combines a spin channel (which can itself be complex) with a boson operator

**Hamiltonian contribution:**
```
H += strength × [spin_channels] ⊗ [boson_op]
```

Where:
- `[spin_channels]` can be any combination of spin channels (PowerLawCoupling, Field, FiniteRangeCoupling, etc.)
- `[boson_op]` is a boson operator

**Configuration:**
```json
{
  "type": "SpinBosonInteraction",
  "spin_channels": [
    {"type": "Field", "op": "Z", "strength": 1.0}
  ],
  "boson_op": "a",
  "strength": 0.2
}
```

**Parameters:**
- `spin_channels` - Array of spin channel configurations (parsed recursively)
- `boson_op` - Boson operator symbol
- `strength` - Overall coupling strength

**Boson operators:**
- `"Ib"` - Boson identity (spin-only term with boson present)
- `"a"` - Annihilation operator
- `"adag"` - Creation operator  
- `"Bn"` - Number operator b†b

**Example:** Spin-Z field coupled to boson annihilation
```json
{
  "type": "SpinBosonInteraction",
  "spin_channels": [
    {"type": "Field", "op": "Z", "strength": 1.0}
  ],
  "boson_op": "a",
  "strength": 0.2
}
```
This creates: `0.2 × (Σᵢ σᶻᵢ) ⊗ a`

---

### Building Custom Models

#### **Example 1: Reconstructing TFIM from Channels**

```json
{
  "model": {
    "name": "custom_spin",
    "params": {
      "N": 40,
      "d": 2,
      "dtype": "Float64",
      "channels": [
        {
          "type": "FiniteRangeCoupling",
          "op1": "Z",
          "op2": "Z",
          "range": 1,
          "strength": -1.0
        },
        {
          "type": "Field",
          "op": "X",
          "strength": 0.5
        }
      ]
    }
  }
}
```

This produces: `H = -Σᵢ σᶻᵢσᶻᵢ₊₁ + 0.5 Σᵢ σˣᵢ`

---

#### **Example 2: Multiple Interaction Ranges**

```json
{
  "channels": [
    {
      "type": "FiniteRangeCoupling",
      "op1": "Z",
      "op2": "Z",
      "range": 1,
      "strength": -1.0
    },
    {
      "type": "FiniteRangeCoupling",
      "op1": "Z",
      "op2": "Z",
      "range": 2,
      "strength": -0.3
    },
    {
      "type": "Field",
      "op": "X",
      "strength": 0.5
    }
  ]
}
```

This produces: `H = -Σᵢ σᶻᵢσᶻᵢ₊₁ - 0.3 Σᵢ σᶻᵢσᶻᵢ₊₂ + 0.5 Σᵢ σˣᵢ`

---

#### **Example 3: Heisenberg from Channels**

```json
{
  "channels": [
    {
      "type": "FiniteRangeCoupling",
      "op1": "X",
      "op2": "X",
      "range": 1,
      "strength": 1.0
    },
    {
      "type": "FiniteRangeCoupling",
      "op1": "Y",
      "op2": "Y",
      "range": 1,
      "strength": 1.0
    },
    {
      "type": "FiniteRangeCoupling",
      "op1": "Z",
      "op2": "Z",
      "range": 1,
      "strength": 1.0
    }
  ]
}
```

---

#### **Example 4: Mixed Channels**

```json
{
  "channels": [
    {
      "type": "FiniteRangeCoupling",
      "op1": "Z",
      "op2": "Z",
      "range": 1,
      "strength": -1.0
    },
    {
      "type": "ExpChannelCoupling",
      "op1": "X",
      "op2": "X",
      "amplitude": 0.5,
      "decay": 0.8
    },
    {
      "type": "Field",
      "op": "Z",
      "strength": 0.1
    }
  ]
}
```

Combines nearest-neighbor Ising + exponentially decaying XX + longitudinal field.

---

#### **Example 5: Spin-Boson Model**

**Physics:** Long-range Ising model coupled to bosonic mode

```
H = J Σᵢ<ⱼ σˣᵢσˣⱼ/|i-j|^α + h Σᵢ σˣᵢ + g(a + a†)Σᵢ σᶻᵢ + ω b†b
```

**Configuration:**
```json
{
  "model": {
    "name": "custom_spinboson",
    "params": {
      "N_spins": 40,
      "nmax": 10,
      "dtype": "Float64",
      "channels": [
        {
          "type": "SpinBosonInteraction",
          "spin_channels": [
            {
              "type": "PowerLawCoupling",
              "op1": "X",
              "op2": "X",
              "strength": -1.0,
              "alpha": 1.5,
              "n_exp": 4,
              "N": 40
            },
            {
              "type": "Field",
              "op": "X",
              "strength": -1.0
            }
          ],
          "boson_op": "Ib",
          "strength": 1.0
        },
        {
          "type": "SpinBosonInteraction",
          "spin_channels": [
            {
              "type": "Field",
              "op": "Z",
              "strength": 1.0
            }
          ],
          "boson_op": "a",
          "strength": 0.2
        },
        {
          "type": "SpinBosonInteraction",
          "spin_channels": [
            {
              "type": "Field",
              "op": "Z",
              "strength": 1.0
            }
          ],
          "boson_op": "adag",
          "strength": 0.2
        },
        {
          "type": "BosonOnly",
          "op": "Bn",
          "strength": 1.0
        }
      ]
    }
  }
}
```

**Breakdown:**
1. **First channel:** Spin-only part (long-range XX + field X) with boson identity
   - `PowerLawCoupling` for J Σᵢ<ⱼ σˣᵢσˣⱼ/|i-j|^1.5
     - `n_exp=4` uses 4 exponentials for decomposition
     - `N=40` sets approximation range
   - `Field` for h Σᵢ σˣᵢ
   - `boson_op: "Ib"` means these terms have boson identity (spin-only)

2. **Second channel:** Spin-boson coupling (annihilation)
   - `Field(:Z)` creates Σᵢ σᶻᵢ
   - `boson_op: "a"` couples to annihilation operator
   - Result: g × (Σᵢ σᶻᵢ) ⊗ a where g=0.2

3. **Third channel:** Spin-boson coupling (creation)
   - Same spin channel Σᵢ σᶻᵢ
   - `boson_op: "adag"` couples to creation operator
   - Result: g × (Σᵢ σᶻᵢ) ⊗ a†

4. **Fourth channel:** Pure boson energy
   - `BosonOnly` with `op="Bn"` (number operator)
   - `strength=1.0` is the boson frequency ω
   - Result: ω b†b

**Key insight:** The `SpinBosonInteraction` allows you to couple **any combination of spin channels** (simple or complex) to **any boson operator**. The `spin_channels` array can contain multiple spin interactions that are combined before coupling to the boson.

---

## Finite State Machine (FSM) Construction

### The Challenge: Long-Range Interactions

Power-law interactions pose a fundamental challenge for MPO-based methods:

**Naive approach:**
```
H = Σᵢ<ⱼ Aᵢ Bⱼ f(|i-j|)
```

Requires MPO bond dimension χ = O(N) because each site must "remember" all previous interactions. For N=100, this becomes computationally prohibitive.

**FSM approach:**
Express f(r) as sum of exponentials:
```
f(r) = Σₖ νₖ λₖʳ
```

Each exponential creates one FSM channel with bond dimension 1. Total: χ = O(n_exp) where n_exp is number of exponentials.

For power-law `f(r) = 1/r^α`, we need n_exp ~ log(N) exponentials for given accuracy, yielding **χ = O(log N)** - exponential improvement!

---

### Sum-of-Exponentials Decomposition

**Problem:** Approximate `1/r^α` by `Σₖ νₖ λₖʳ` on interval [1, N]

**Method:** QR decomposition approach (SciPost Phys. 12, 126 (2022), Appendix C)

**Implementation in TNCodebase:**

The function `_power_law_to_exp(alpha, N, n_exp)` in `src/Core/fsm.jl`:

1. Constructs Vandermonde-like matrix for r ∈ [1, N]
2. Uses QR decomposition to find optimal λₖ
3. Solves least-squares for optimal νₖ
4. Returns `(λ_values, ν_values)`

**Parameters:**
- `alpha` - Power-law exponent
- `N` - System size (determines approximation range)
- `n_exp` - Number of exponentials (accuracy vs. bond dimension trade-off)

**Typical values:**
- n_exp = 5-10: Good for α ~ 1-2, N ~ 50-100
- n_exp = 10-15: Better accuracy or larger systems
- n_exp = 20+: Rarely needed (diminishing returns)

---

### FSM Structure

**For each exponential channel:**

```
FSM: START → [channel] → END
         λ        ν
```

**Multiple channels combine:**

```
FSM: START → [channel 1] → END
           → [channel 2] → END
           → [channel 3] → END
           → [field]    → END
```

**MPO structure:**

```
Site i:   W[i] = [χ_left × d × d × χ_right]

Boundary:  W[1]   has χ_left = 1   (START)
           W[N]   has χ_right = 1  (END)

Bulk:      W[i]   transitions between FSM states
```

**Bond dimension:**
```
χ = 1 + (# of channels) + 1 = # channels + 2
```

For power-law with n_exp exponentials: χ = n_exp + 2 (plus any additional channels)

### Verifying Decomposition Quality

**Check approximation error:**

```julia
using TNCodebase

# Get decomposition (n_exp=10 exponentials)
λ_vals, ν_vals = TNCodebase._power_law_to_exp(1.5, 100, 10)

# Compute approximation
function approx_power_law(r, λ_vals, ν_vals)
    return sum(ν_vals[k] * λ_vals[k]^r for k in 1:length(λ_vals))
end

# Compare to exact
exact(r) = 1.0 / r^1.5
approx(r) = approx_power_law(r, λ_vals, ν_vals)

# Compute error
errors = [abs(approx(r) - exact(r)) / exact(r) for r in 1:100]
max_error = maximum(errors)
println("Maximum relative error: ", max_error)
```

---

## Advanced Topics

### Type System

**Generic types:**
```julia
MPO{T} where T <: Number
```

**Supported types:**
- `Float64` - Real-valued Hamiltonians (fastest)
- `ComplexF64` - Complex Hamiltonians (e.g., with imaginary fields)

**Type promotion:**
```julia
MPO{Float64} + MPO{ComplexF64} → MPO{ComplexF64}
```

**Specify in config:**
```json
{
  "model": {
    "params": {
      "dtype": "ComplexF64"
    }
  }
}
```

---

### Performance Considerations

**Channel ordering:**
- No performance impact (channels combine additively)
- Order affects only readability

**FSM optimization:**
- `PowerLawCoupling` automatically optimizes
- Exponential channels are efficient
- `FiniteRangeCoupling` with large range increases χ linearly

**Memory scaling:**
```
MPO memory ~ N × χ² × d² × sizeof(T)
```

For N=100, χ=20, d=2, Float64:
```
Memory ~ 100 × 400 × 4 × 8 bytes = 1.3 MB
```

**Recommendation:** Keep χ < 100 for practical simulations

---

### Numerical Stability

**Exponential decay channels:**
- Choose λ < 0.99 to avoid numerical issues
- Very small λ (< 0.1) may cause precision loss

**Power-law channels:**
- Very large α (> 5) better handled as `FiniteRangeCoupling`

**Field strengths:**
- Avoid extreme values (|strength| > 100) without rescaling

---

## Extension Guide: Adding Custom Channel Types

### When to Add a New Channel

**Add a new channel type when:**
- Interaction has specific functional form (e.g., Gaussian decay)
- Requires specialized FSM construction
- Used frequently in your research

**Don't add if:**
- Can be approximated by existing channels
- One-off use case

---

### Implementation Steps

**1. Define channel struct in `src/Core/fsm.jl`:**

```julia
struct GaussianCoupling
    op1::Symbol
    op2::Symbol
    sigma::Float64
    strength::Float64
end
```

**2. Add FSM transition in `build_FSM`:**

```julia
function build_FSM(channel::GaussianCoupling, sites, N)
    # Approximate Gaussian as sum of exponentials
    λ_vals, ν_vals = _gaussian_to_exp(channel.sigma, N)
    
    # Build exponential channels with correct parameters
    channels = [ExpChannelCoupling(channel.op1, channel.op2, ν * channel.strength, λ)
                for (λ, ν) in zip(λ_vals, ν_vals)]
    
    # Combine FSMs
    return combine_FSMs([build_FSM(c, sites, N) for c in channels])
end
```

**3. Add parser in `src/Builders/modelbuilder.jl`:**

```julia
function parse_channel_dict(d::Dict)
    if d["type"] == "GaussianCoupling"
        return GaussianCoupling(
            Symbol(d["op1"]),
            Symbol(d["op2"]),
            d["sigma"],
            d["strength"]
        )
    end
    # ... existing types ...
end
```

**4. Export in `src/TNCodebase.jl`:**

```julia
export GaussianCoupling
```

**5. Test:**

```julia
config = Dict(
    "channels" => [
        Dict("type" => "GaussianCoupling",
             "op1" => "Z", "op2" => "Z",
             "sigma" => 2.0, "strength" => 1.0)
    ]
)
```

---

### Adding Prebuilt Model Templates

**1. Define channel generator in `src/Builders/modelbuilder.jl`:**

```julia
function get_my_model_channels(N, params)
    channels = []
    
    # Add required channels
    push!(channels, FiniteRangeCoupling(:Z, :Z, 1, params["J"]))
    push!(channels, Field(:X, params["h"]))
    
    # Conditional channels
    if haskey(params, "next_nearest")
        push!(channels, FiniteRangeCoupling(:Z, :Z, 2, params["next_nearest"]))
    end
    
    return channels
end
```

**2. Add to parser:**

```julia
function parse_spin_channels(model_dict)
    if model_dict["name"] == "my_model"
        return get_my_model_channels(
            model_dict["params"]["N"],
            model_dict["params"]
        )
    end
    # ... existing templates ...
end
```

**3. Document in this file and in example**

---

## Summary

TNCodebase's model building system provides:

**Flexibility:**
- Prebuilt templates for standard models
- Channel system for custom Hamiltonians
- Easy composition of interaction types

**Efficiency:**
- FSM-based MPO construction
- Optimized bond dimensions
- Power-law decomposition

**Extensibility:**
- Add custom channel types
- Define new templates
- Modify existing channels

**Best practices:**
- Start with prebuilt models
- Use custom channels for novel physics
- Verify FSM accuracy for power-law interactions
- Keep MPO bond dimension manageable (χ < 100)

For working examples, see:
- `examples/models/prebuilt/` - Template usage
- `examples/models/custom/` - Channel construction
- `examples/models/custom/advanced_fsm/` - FSM details

For implementation details, see:
- `src/Core/fsm.jl` - FSM construction
- `src/Builders/modelbuilder.jl` - Model parsing
- `src/Builders/mpobuilder.jl` - MPO construction
