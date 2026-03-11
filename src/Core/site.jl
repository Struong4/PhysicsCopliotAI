using LinearAlgebra 

function spin_ops(d::Integer)
    @assert d ≥ 1 "d must be ≥ 1"
    # total spin S and its m‐values
    S = (d - 1)/2
    m_vals = collect(S:-1:-S)   # [S, S-1, …, -S]

    # Sz is just diagonal of m_vals
    Sz = Diagonal(m_vals)

    # Build S+ and S– by placing coef on the super/sub‐diagonal
    Sp = zeros(Float64, d, d)
    @inbounds for i in 1:d-1
        m_lower = m_vals[i+1]   # THIS is the m of the state being raised
        coef = sqrt((S - m_lower)*(S + m_lower + 1))
        Sp[i, i+1] = coef
    end
    Sm = Sp'  # adjoint

    # Now the cartesian components
    Sx = (Sp + Sm)/2
    Sy = (Sp - Sm) / (2im)

    return Dict(:X => Sx,
                :Y => Sy, 
                :Z => Sz,
                :Sp => Sp,
                :Sm => Sm, 
                :I => Matrix{Float64}(I, d, d))
end

function _boson_annihilator(nmax::Integer)
    @assert nmax ≥ 0 "nmax must be non-negative"
    dB = nmax + 1
    A = zeros(Float64, dB, dB)
    @inbounds for k in 1:nmax                 # super-diagonal entries
        A[k, k+1] = sqrt(k)              # √k = √(n) with n=k
    end
    return A
end

function _boson_identity(nmax::Integer)
    dB = nmax + 1
    I = zeros(Float64, dB, dB)          # or zeros(n,n) if Float64 is fine
    @inbounds for k in 1:dB                    # i ↔ n in the formula above
        I[k, k] = 1.0          # diagonal entry
    end
    return I
end 

function boson_ops(nmax::Integer)
    a    = _boson_annihilator(nmax)
    adag = a'
    return Dict(
      :a    => a,
      :adag => adag,
      :Bn    => adag * a,
      :Ib   => _boson_identity(nmax),
    )
end

# ──────────────────────────────────────────────────────────────────────────────
# Abstract supertype
#───────────────────────────────────────────────────────────────────────────────

"""
    AbstractSite{T}

A common supertype for all single‐site objects (spins, bosons, etc.).
"""
abstract type AbstractSite{T} end


struct SpinSite{T} <: AbstractSite{T}
    dim::Int
    ops::Dict             # :X,:Y,:Z,…
    spectra::Dict  # precomputed eigvals/vecs
end
  
function SpinSite(S::Real; T=ComplexF64)
    d   = Int(2S + 1)
    # Always store operators as ComplexF64 (σʸ is inherently complex)
    ops = Dict{Symbol,Matrix{ComplexF64}}()
    spectra = Dict{Symbol,Tuple{Vector{Float64},Matrix{ComplexF64}}}()
    raw = spin_ops(d)
    for ax in (:X,:Y,:Z)
        mat = ComplexF64.(raw[ax])
        E = eigen(Hermitian(mat))
        idx = sortperm(E.values)
        ops[ax] = mat
        spectra[ax] = (real.(E.values[idx]), ComplexF64.(E.vectors[:,idx]))
    end
    return SpinSite{T}(d,ops,spectra)
end

struct BosonSite{T} <: AbstractSite{T}
    dim::Int
    op::Matrix{T}           # Bn operator
    eigvals::Vector{T}
    eigvecs::Matrix{T}
end

function BosonSite(nmax::Int; T=Float64)
    E   = eigen(boson_ops(nmax)[:Bn])
    idx = sortperm(E.values)
    return BosonSite{T}(nmax+1,
                        boson_ops(nmax)[:Bn],
                        E.values[idx],
                        E.vectors[:, idx])
end

"""
    state_tensor(site::BosonSite, n::Int)

Return the (1,d,1) tensor for boson‐level `n` (0 ≤ n ≤ nmax).
"""

function _state_tensor(site::BosonSite{T}, n::Int) where T
    @assert 0 ≤ n ≤ site.dim-1 "Boson level out of range"
    return reshape(site.eigvecs[:, n+1], 1, site.dim, 1)
end

"""
    state_tensor(site::SpinSite, label::Pair{Symbol,Int})

Return the (1,d,1) tensor for the `k`th eigenvector (ascending) of `axis`.
"""

function _state_tensor(site::SpinSite{T}, label::Tuple{Symbol,Int}) where T
    ax, k = label
    vals, vecs = site.spectra[ax]
    @assert 1 ≤ k ≤ length(vals)
    return reshape(vecs[:,k], 1, site.dim, 1)
end