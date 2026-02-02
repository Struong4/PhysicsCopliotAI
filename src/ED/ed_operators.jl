# ============================================================================
# ED OPERATORS - Local Operator Matrices
# ============================================================================
#
# Provides spin and boson operator matrices for exact diagonalization.
# Equivalent to Core/site.jl in TN, but outputs full matrices (not site objects).
#
# USAGE:
#   spin_ops = spin_matrices(S=0.5)      # Dict(:X => Sx, :Y => Sy, ...)
#   boson_ops = boson_matrices(nmax=4)   # Dict(:a => a, :adag => a†, ...)
#
# ============================================================================

using LinearAlgebra
using SparseArrays

# ============================================================================
# PART 1: SPIN OPERATORS
# ============================================================================

"""
    spin_matrices(S; T=ComplexF64) -> Dict{Symbol, SparseMatrixCSC}

Generate spin operators for spin-S system.

# Arguments
- `S::Real`: Spin quantum number (0.5, 1, 1.5, ...)
- `T::Type`: Element type (default: ComplexF64)

# Returns
Dict with keys:
- `:X`, `:Y`, `:Z` — Pauli matrices (scaled by S for S > 1/2)
- `:Sp`, `:Sm` — Raising/lowering operators
- `:I` — Identity

# Examples
```julia
ops = spin_matrices(0.5)
Sz = ops[:Z]  # Diagonal: [0.5, -0.5]

ops = spin_matrices(1)
Sz = ops[:Z]  # Diagonal: [1, 0, -1]
```
"""
function spin_matrices(S::Real; T::Type=ComplexF64)
    d = Int(2S + 1)
    
    # m values: S, S-1, ..., -S
    m_vals = collect(range(S, -S, length=d))
    
    # Sz is diagonal
    Sz = spdiagm(0 => T.(m_vals))
    
    # S+ raising operator (superdiagonal)
    # S+ |S,m⟩ = √[(S-m)(S+m+1)] |S,m+1⟩
    Sp_diag = T[sqrt((S - m_vals[i+1]) * (S + m_vals[i+1] + 1)) for i in 1:d-1]
    Sp = spdiagm(1 => Sp_diag)
    
    # S- lowering operator (subdiagonal)
    Sm = sparse(Sp')
    
    # Sx = (S+ + S-) / 2
    Sx = (Sp + Sm) / 2
    
    # Sy = (S+ - S-) / 2i
    Sy = (Sp - Sm) / (2im)
    
    # Identity
    Id = sparse(one(T) * I, d, d)
    
    return Dict{Symbol, SparseMatrixCSC{T, Int}}(
        :X  => Sx,
        :Y  => Sy,
        :Z  => Sz,
        :Sp => Sp,
        :Sm => Sm,
        :I  => Id
    )
end

# ============================================================================
# PART 2: BOSON OPERATORS
# ============================================================================

"""
    boson_matrices(nmax; T=ComplexF64) -> Dict{Symbol, SparseMatrixCSC}

Generate boson operators with Fock space truncated at nmax.

# Arguments
- `nmax::Int`: Maximum occupation number (Fock space dimension = nmax + 1)
- `T::Type`: Element type (default: ComplexF64)

# Returns
Dict with keys:
- `:a` — Annihilation operator
- `:adag` — Creation operator
- `:Bn` — Number operator (a†a)
- `:Ib` — Identity

# Examples
```julia
ops = boson_matrices(4)
a = ops[:a]       # Annihilation
n = ops[:Bn]      # Number operator, diagonal: [0, 1, 2, 3, 4]
```
"""
function boson_matrices(nmax::Int; T::Type=ComplexF64)
    @assert nmax >= 0 "nmax must be non-negative"
    
    d = nmax + 1
    
    # Annihilation operator: a|n⟩ = √n |n-1⟩
    # Matrix elements: a[n, n+1] = √(n+1) for n = 0, 1, ..., nmax-1
    a_diag = T[sqrt(n) for n in 1:nmax]
    a = spdiagm(1 => a_diag)
    
    # Creation operator: a†|n⟩ = √(n+1) |n+1⟩
    adag = sparse(a')
    
    # Number operator: n = a†a
    n_diag = T.(0:nmax)
    Bn = spdiagm(0 => n_diag)
    
    # Identity
    Ib = sparse(one(T) * I, d, d)
    
    return Dict{Symbol, SparseMatrixCSC{T, Int}}(
        :a    => a,
        :adag => adag,
        :Bn   => Bn,
        :Ib   => Ib
    )
end

# ============================================================================
# PART 3: CONVENIENCE FUNCTIONS
# ============================================================================

"""
    local_dim_spin(S) -> Int

Return local Hilbert space dimension for spin-S.
"""
function local_dim_spin(S::Real)
    return Int(2S + 1)
end

"""
    local_dim_boson(nmax) -> Int

Return local Hilbert space dimension for boson with cutoff nmax.
"""
function local_dim_boson(nmax::Int)
    return nmax + 1
end

"""
    get_operator(ops::Dict, name::Symbol) -> SparseMatrixCSC

Retrieve operator from dictionary with error checking.
"""
function get_operator(ops::Dict{Symbol, <:AbstractMatrix}, name::Symbol)
    haskey(ops, name) || error("Unknown operator: $name. Available: $(keys(ops))")
    return ops[name]
end

"""
    all_spin_operators() -> Vector{Symbol}

List all available spin operator names.
"""
function all_spin_operators()
    return [:X, :Y, :Z, :Sp, :Sm, :I]
end

"""
    all_boson_operators() -> Vector{Symbol}

List all available boson operator names.
"""
function all_boson_operators()
    return [:a, :adag, :Bn, :Ib]
end