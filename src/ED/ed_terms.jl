# ============================================================================
# ED TERMS - Physics Specification for Hamiltonians
# ============================================================================
#
# Defines term types that specify Hamiltonian physics.
# Equivalent to Core/fsm.jl Channel types in TN.
#
# TERM TYPES:
#   Spin:
#     - EDField          : Single-site field (h Σᵢ σᵢ)
#     - EDCoupling       : Two-site coupling (Σᵢⱼ f(i,j) σᵢσⱼ)
#
#   Boson:
#     - EDBosonTerm      : Boson-only term (ω b†b)
#     - EDSpinBosonCoupling : Spin-boson interaction (g b Σᵢ σᵢ)
#
# USAGE:
#   terms = [
#       EDCoupling(:Z, :Z, (i,j,N) -> j == i+1 ? J : 0.0),
#       EDField(:X, h)
#   ]
#   H = build_H_spin(N, S, terms)
#
# ============================================================================

# ============================================================================
# PART 1: ABSTRACT TYPE
# ============================================================================

"""
    EDTerm

Abstract supertype for all ED Hamiltonian terms.
Subtypes define specific interaction patterns.
"""
abstract type EDTerm end

# ============================================================================
# PART 2: SPIN TERMS
# ============================================================================

"""
    EDField(op, strength)

Single-site field term: strength × Σᵢ opᵢ

# Arguments
- `op::Symbol`: Operator name (:X, :Y, :Z, :Sp, :Sm)
- `strength::Float64`: Field strength

# Example
```julia
# Transverse field: h Σᵢ σˣᵢ
EDField(:X, 0.5)

# Longitudinal field: hz Σᵢ σᶻᵢ
EDField(:Z, 1.0)
```

# TN Equivalent
`Field` in Core/fsm.jl
"""
struct EDField <: EDTerm
    op::Symbol
    strength::Float64
end

"""
    EDCoupling(op1, op2, coeff)

Two-site coupling term: Σᵢⱼ coeff(i,j,N) × op1ᵢ × op2ⱼ

Coefficient function allows any interaction pattern:
- Nearest neighbor: (i,j,N) -> j == i+1 ? J : 0.0
- All-to-all: (i,j,N) -> i < j ? J : 0.0
- Power law: (i,j,N) -> i < j ? J/abs(i-j)^α : 0.0

# Arguments
- `op1::Symbol`: Operator on site i
- `op2::Symbol`: Operator on site j
- `coeff::Function`: (i, j, N) → Float64

# Examples
```julia
# Nearest-neighbor ZZ: J Σᵢ σᶻᵢσᶻᵢ₊₁
EDCoupling(:Z, :Z, (i,j,N) -> j == i+1 ? 1.0 : 0.0)

# Long-range Ising (EXACT): J Σᵢ<ⱼ σᶻᵢσᶻⱼ / |i-j|^α
EDCoupling(:Z, :Z, (i,j,N) -> i < j ? 1.0/abs(i-j)^1.5 : 0.0)

# Periodic boundary: J Σᵢ σᶻᵢσᶻᵢ₊₁ (with wrap)
EDCoupling(:Z, :Z, (i,j,N) -> (j == i+1 || (i==N && j==1)) ? 1.0 : 0.0)
```

# TN Equivalent
`FiniteRangeCoupling`, `ExpChannelCoupling`, `PowerLawCoupling` in Core/fsm.jl
(ED combines all into one flexible type with exact coefficients)
"""
struct EDCoupling <: EDTerm
    op1::Symbol
    op2::Symbol
    coeff::Function  # (i::Int, j::Int, N::Int) -> Float64
end

# ============================================================================
# PART 3: BOSON TERMS
# ============================================================================

"""
    EDBosonTerm(op, strength)

Boson-only term acting on cavity: strength × op

# Arguments
- `op::Symbol`: Boson operator (:a, :adag, :Bn)
- `strength::Float64`: Coefficient

# Examples
```julia
# Cavity frequency: ω b†b
EDBosonTerm(:Bn, 1.5)

# Drive term: ε (b + b†)
# (would need two terms)
EDBosonTerm(:a, 0.1)
EDBosonTerm(:adag, 0.1)
```

# TN Equivalent
`BosonOnly` in Core/fsm.jl
"""
struct EDBosonTerm <: EDTerm
    op::Symbol
    strength::Float64
end

"""
    EDSpinBosonCoupling(boson_op, spin_op, strength)

Spin-boson interaction: strength × boson_op × Σᵢ spin_opᵢ

Couples cavity mode to collective spin operator.

# Arguments
- `boson_op::Symbol`: Boson operator (:a, :adag)
- `spin_op::Symbol`: Spin operator (:X, :Y, :Z, :Sp, :Sm)
- `strength::Float64`: Coupling strength

# Examples
```julia
# Dicke coupling: g (b + b†) Σᵢ σˣᵢ
EDSpinBosonCoupling(:a, :X, 0.5)
EDSpinBosonCoupling(:adag, :X, 0.5)

# Jaynes-Cummings (rotating wave): g (b σ⁺ + b† σ⁻)
EDSpinBosonCoupling(:a, :Sp, 0.5)
EDSpinBosonCoupling(:adag, :Sm, 0.5)
```

# TN Equivalent
`SpinBosonInteraction` in Core/fsm.jl
"""
struct EDSpinBosonCoupling <: EDTerm
    boson_op::Symbol
    spin_op::Symbol
    strength::Float64
end

# ============================================================================
# PART 4: CONVENIENCE CONSTRUCTORS
# ============================================================================

"""
    nearest_neighbor(op1, op2, J) -> EDCoupling

Create nearest-neighbor coupling: J Σᵢ op1ᵢ op2ᵢ₊₁
"""
function nearest_neighbor(op1::Symbol, op2::Symbol, J::Real)
    return EDCoupling(op1, op2, (i, j, N) -> j == i + 1 ? Float64(J) : 0.0)
end

"""
    nearest_neighbor_periodic(op1, op2, J) -> EDCoupling

Create nearest-neighbor coupling with periodic boundary.
"""
function nearest_neighbor_periodic(op1::Symbol, op2::Symbol, J::Real)
    return EDCoupling(op1, op2, 
        (i, j, N) -> (j == i + 1 || (i == N && j == 1)) ? Float64(J) : 0.0)
end

"""
    power_law(op1, op2, J, alpha) -> EDCoupling

Create power-law coupling: J Σᵢ<ⱼ op1ᵢ op2ⱼ / |i-j|^α

Note: This is EXACT, unlike TN which approximates with sum of exponentials.
"""
function power_law(op1::Symbol, op2::Symbol, J::Real, alpha::Real)
    return EDCoupling(op1, op2, 
        (i, j, N) -> i < j ? Float64(J) / abs(i - j)^Float64(alpha) : 0.0)
end

"""
    all_to_all(op1, op2, J) -> EDCoupling

Create all-to-all coupling: J Σᵢ<ⱼ op1ᵢ op2ⱼ
"""
function all_to_all(op1::Symbol, op2::Symbol, J::Real)
    return EDCoupling(op1, op2, 
        (i, j, N) -> i < j ? Float64(J) : 0.0)
end

"""
    finite_range(op1, op2, J, range) -> EDCoupling

Create finite-range coupling: J Σᵢ op1ᵢ op2ᵢ₊ᵣ
"""
function finite_range(op1::Symbol, op2::Symbol, J::Real, range::Int)
    return EDCoupling(op1, op2, 
        (i, j, N) -> j == i + range ? Float64(J) : 0.0)
end

"""
    finite_range_periodic(op1, op2, J, range) -> EDCoupling

Create finite-range coupling with periodic boundary: J Σᵢ op1ᵢ op2ᵢ₊ᵣ (mod N)

Sites wrap around: site N+1 → site 1, site N+2 → site 2, etc.
"""
function finite_range_periodic(op1::Symbol, op2::Symbol, J::Real, range::Int)
    return EDCoupling(op1, op2, 
        (i, j, N) -> j == mod1(i + range, N) ? Float64(J) : 0.0)
end

# ============================================================================
# PART 5: VALIDATION
# ============================================================================

"""
    validate_spin_term(term::EDTerm) -> Bool

Check if term uses valid spin operators.
"""
function validate_spin_term(term::EDTerm)
    valid_ops = [:X, :Y, :Z, :Sp, :Sm, :I]
    
    if term isa EDField
        return term.op in valid_ops
    elseif term isa EDCoupling
        return term.op1 in valid_ops && term.op2 in valid_ops
    end
    
    return false
end

"""
    validate_boson_term(term::EDTerm) -> Bool

Check if term uses valid boson operators.
"""
function validate_boson_term(term::EDTerm)
    valid_spin = [:X, :Y, :Z, :Sp, :Sm, :I]
    valid_boson = [:a, :adag, :Bn, :Ib]
    
    if term isa EDBosonTerm
        return term.op in valid_boson
    elseif term isa EDSpinBosonCoupling
        return term.boson_op in valid_boson && term.spin_op in valid_spin
    end
    
    return false
end

"""
    is_spin_term(term::EDTerm) -> Bool

Check if term is a pure spin term.
"""
function is_spin_term(term::EDTerm)
    return term isa EDField || term isa EDCoupling
end

"""
    is_boson_term(term::EDTerm) -> Bool

Check if term involves bosons.
"""
function is_boson_term(term::EDTerm)
    return term isa EDBosonTerm || term isa EDSpinBosonCoupling
end

# ============================================================================
# PART 6: DISPLAY
# ============================================================================

function Base.show(io::IO, t::EDField)
    print(io, "EDField($(t.op), strength=$(t.strength))")
end

function Base.show(io::IO, t::EDCoupling)
    print(io, "EDCoupling($(t.op1), $(t.op2), <coeff_function>)")
end

function Base.show(io::IO, t::EDBosonTerm)
    print(io, "EDBosonTerm($(t.op), strength=$(t.strength))")
end

function Base.show(io::IO, t::EDSpinBosonCoupling)
    print(io, "EDSpinBosonCoupling($(t.boson_op) ⊗ $(t.spin_op), strength=$(t.strength))")
end