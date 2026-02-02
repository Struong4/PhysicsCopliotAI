# ============================================================================
# ED OBSERVABLES - Measurement Functions (TN-Compatible Naming)
# ============================================================================
#
# Provides functions to measure physical observables from ED state vectors.
# Function names match TN Analysis_*.jl for consistency.
# Multiple dispatch distinguishes ED (AbstractVector) from TN (Vector{Array{T,3}}).
#
# NAMING CONVENTION (matches TN):
#   single_site_expectation  - Local ⟨Oᵢ⟩
#   two_site_expectation     - Two-point ⟨OᵢPⱼ⟩ (different operators)
#   correlation_function     - Two-point ⟨OᵢOⱼ⟩ (same operator)
#   connected_correlation    - Connected ⟨OᵢOⱼ⟩ - ⟨Oᵢ⟩⟨Oⱼ⟩
#   entanglement_entropy     - von Neumann / Renyi entropy
#   entanglement_spectrum    - Schmidt values
#   energy_expectation       - ⟨H⟩
#   energy_variance          - ⟨H²⟩ - ⟨H⟩²
#
# SPIN-BOSON: Add _sb suffix (e.g., single_site_expectation_sb)
#
# ============================================================================

using LinearAlgebra
using SparseArrays

# ============================================================================
# PART 1: LOCAL OBSERVABLES (SPIN-ONLY)
# ============================================================================

"""
    single_site_expectation(site, operator, psi, N, S; T=ComplexF64) -> Float64

Calculate single-site expectation value ⟨ψ|Oᵢ|ψ⟩.

Matches TN signature: `single_site_expectation(site, operator, psi)`
ED adds N, S parameters for Hilbert space construction.

# Arguments
- `site::Int`: Site index where operator is applied
- `operator`: Local operator (Symbol like :Z or Matrix)
- `psi::AbstractVector`: State vector
- `N::Int`: Number of sites
- `S::Real`: Spin quantum number

# Example
```julia
# Using Symbol (convenience)
Sz_3 = single_site_expectation(3, :Z, psi, 10, 0.5)

# Using matrix (like TN)
Sz = [0.5 0; 0 -0.5]
Sz_3 = single_site_expectation(3, Sz, psi, 10, 0.5)
```
"""
function single_site_expectation(site::Int, operator::AbstractMatrix, 
                                  psi::AbstractVector{<:Number}, N::Int, S::Real;
                                  T::Type=ComplexF64)
    d = Int(2S + 1)
    O = embed_operator(Matrix{T}(operator), site, N, d, T=T)
    return real(dot(psi, O * psi))
end

# Convenience method with Symbol
function single_site_expectation(site::Int, op::Symbol, 
                                  psi::AbstractVector{<:Number}, N::Int, S::Real;
                                  T::Type=ComplexF64)
    ops = spin_matrices(S, T=T)
    return single_site_expectation(site, ops[op], psi, N, S, T=T)
end

"""
    expectation_value_all_sites(operator, psi, N, S; T=ComplexF64) -> Vector{Float64}

Measure local expectation value on all sites.

# Returns
Vector of length N: [⟨O₁⟩, ⟨O₂⟩, ..., ⟨Oₙ⟩]

# Example
```julia
Sz_profile = expectation_value_all_sites(:Z, psi, 10, 0.5)
```
"""
function expectation_value_all_sites(operator, psi::AbstractVector{<:Number}, 
                                      N::Int, S::Real; T::Type=ComplexF64)
    return [single_site_expectation(i, operator, psi, N, S, T=T) for i in 1:N]
end

"""
    subsystem_expectation_sum(operator, psi, l, m, N, S; T=ComplexF64) -> Float64

Compute sum of expectation values ⟨Σᵢ Oᵢ⟩ for sites i ∈ [l, m].

Matches TN signature: `subsystem_expectation_sum(operator, psi, l, m)`

# Arguments
- `operator`: Local operator (Symbol or Matrix)
- `psi::AbstractVector`: State vector
- `l::Int`: Starting site (1 ≤ l ≤ N)
- `m::Int`: Ending site (l ≤ m ≤ N)
- `N::Int`: Number of sites
- `S::Real`: Spin quantum number

# Example
```julia
# Total magnetization
total_Sz = subsystem_expectation_sum(:Z, psi, 1, N, N, 0.5)

# Central region magnetization
center_Sz = subsystem_expectation_sum(:Z, psi, 40, 60, 100, 0.5)
```
"""
function subsystem_expectation_sum(operator::AbstractMatrix, 
                                    psi::AbstractVector{<:Number},
                                    l::Int, m::Int, N::Int, S::Real;
                                    T::Type=ComplexF64)
    @assert 1 ≤ l ≤ m ≤ N "Invalid range: must have 1 ≤ l ≤ m ≤ N"
    d = Int(2S + 1)
    
    # Build collective operator for subsystem
    D = d^N
    O_total = spzeros(T, D, D)
    
    for i in l:m
        O_total += embed_operator(Matrix{T}(operator), i, N, d, T=T)
    end
    
    return real(dot(psi, O_total * psi))
end

function subsystem_expectation_sum(op::Symbol, psi::AbstractVector{<:Number},
                                    l::Int, m::Int, N::Int, S::Real;
                                    T::Type=ComplexF64)
    ops = spin_matrices(S, T=T)
    return subsystem_expectation_sum(ops[op], psi, l, m, N, S, T=T)
end

"""
    total_magnetization(psi, N, S, direction=:Z; T=ComplexF64) -> Float64

Convenience function for total spin in given direction.
Equivalent to `subsystem_expectation_sum(direction, psi, 1, N, N, S)`.
"""
function total_magnetization(psi::AbstractVector{<:Number}, N::Int, S::Real,
                              direction::Symbol=:Z; T::Type=ComplexF64)
    return subsystem_expectation_sum(direction, psi, 1, N, N, S, T=T)
end

# ============================================================================
# PART 2: CORRELATION FUNCTIONS (SPIN-ONLY)
# ============================================================================

"""
    two_site_expectation(site_i, op_i, site_j, op_j, psi, N, S; T=ComplexF64) -> Float64

Compute two-site expectation value ⟨ψ|OᵢPⱼ|ψ⟩ with different operators.

Matches TN signature: `two_site_expectation(site_i, op_i, site_j, op_j, psi)`

# Arguments
- `site_i::Int`: First site
- `op_i`: Operator at site i (Symbol or Matrix)
- `site_j::Int`: Second site
- `op_j`: Operator at site j (Symbol or Matrix)
- `psi::AbstractVector`: State vector
- `N::Int`: Number of sites
- `S::Real`: Spin quantum number

# Example
```julia
# ⟨Sᶻ₅ Sˣ₁₀⟩
corr = two_site_expectation(5, :Z, 10, :X, psi, 20, 0.5)
```
"""
function two_site_expectation(site_i::Int, op_i::AbstractMatrix,
                               site_j::Int, op_j::AbstractMatrix,
                               psi::AbstractVector{<:Number}, N::Int, S::Real;
                               T::Type=ComplexF64)
    d = Int(2S + 1)
    
    if site_i == site_j
        # Same site: measure op_i * op_j
        O = embed_operator(Matrix{T}(op_i * op_j), site_i, N, d, T=T)
    else
        O = embed_two_site(Matrix{T}(op_i), Matrix{T}(op_j), site_i, site_j, N, d, T=T)
    end
    
    return real(dot(psi, O * psi))
end

function two_site_expectation(site_i::Int, op_i::Symbol,
                               site_j::Int, op_j::Symbol,
                               psi::AbstractVector{<:Number}, N::Int, S::Real;
                               T::Type=ComplexF64)
    ops = spin_matrices(S, T=T)
    return two_site_expectation(site_i, ops[op_i], site_j, ops[op_j], psi, N, S, T=T)
end

# Mixed: Symbol and Matrix
function two_site_expectation(site_i::Int, op_i::Symbol,
                               site_j::Int, op_j::AbstractMatrix,
                               psi::AbstractVector{<:Number}, N::Int, S::Real;
                               T::Type=ComplexF64)
    ops = spin_matrices(S, T=T)
    return two_site_expectation(site_i, ops[op_i], site_j, op_j, psi, N, S, T=T)
end

function two_site_expectation(site_i::Int, op_i::AbstractMatrix,
                               site_j::Int, op_j::Symbol,
                               psi::AbstractVector{<:Number}, N::Int, S::Real;
                               T::Type=ComplexF64)
    ops = spin_matrices(S, T=T)
    return two_site_expectation(site_i, op_i, site_j, ops[op_j], psi, N, S, T=T)
end

"""
    correlation_function(site_i, site_j, operator, psi, N, S; T=ComplexF64) -> Float64

Compute correlation function ⟨OᵢOⱼ⟩ with same operator at both sites.

Matches TN signature: `correlation_function(site_i, site_j, operator, psi)`

# Arguments
- `site_i::Int`: First site
- `site_j::Int`: Second site
- `operator`: Operator to apply at both sites (Symbol or Matrix)
- `psi::AbstractVector`: State vector
- `N::Int`: Number of sites
- `S::Real`: Spin quantum number

# Example
```julia
ZZ_corr = correlation_function(5, 15, :Z, psi, 20, 0.5)
```
"""
function correlation_function(site_i::Int, site_j::Int, operator,
                               psi::AbstractVector{<:Number}, N::Int, S::Real;
                               T::Type=ComplexF64)
    return two_site_expectation(site_i, operator, site_j, operator, psi, N, S, T=T)
end

# Alias for compatibility
const two_point_correlation = correlation_function

"""
    connected_correlation(site_i, site_j, operator, psi, N, S; T=ComplexF64) -> Float64

Compute connected correlation ⟨OᵢOⱼ⟩ - ⟨Oᵢ⟩⟨Oⱼ⟩.

Matches TN signature: `connected_correlation(site_i, site_j, operator, psi)`

# Example
```julia
conn_ZZ = connected_correlation(10, 20, :Z, psi, 30, 0.5)
```
"""
function connected_correlation(site_i::Int, site_j::Int, operator,
                                psi::AbstractVector{<:Number}, N::Int, S::Real;
                                T::Type=ComplexF64)
    raw_corr = correlation_function(site_i, site_j, operator, psi, N, S, T=T)
    exp_i = single_site_expectation(site_i, operator, psi, N, S, T=T)
    exp_j = single_site_expectation(site_j, operator, psi, N, S, T=T)
    return raw_corr - exp_i * exp_j
end

"""
    correlation_matrix(operator, psi, N, S; T=ComplexF64) -> Matrix{Float64}

Compute full correlation matrix Cᵢⱼ = ⟨OᵢOⱼ⟩.

# Returns
N × N matrix of correlations

# Example
```julia
C_zz = correlation_matrix(:Z, psi, 10, 0.5)
```
"""
function correlation_matrix(operator, psi::AbstractVector{<:Number},
                             N::Int, S::Real; T::Type=ComplexF64)
    C = zeros(Float64, N, N)
    for i in 1:N, j in 1:N
        C[i, j] = correlation_function(i, j, operator, psi, N, S, T=T)
    end
    return C
end

"""
    connected_correlation_matrix(operator, psi, N, S; T=ComplexF64) -> Matrix{Float64}

Compute full connected correlation matrix Cᵢⱼ = ⟨OᵢOⱼ⟩ - ⟨Oᵢ⟩⟨Oⱼ⟩.
"""
function connected_correlation_matrix(operator, psi::AbstractVector{<:Number},
                                       N::Int, S::Real; T::Type=ComplexF64)
    C = zeros(Float64, N, N)
    for i in 1:N, j in 1:N
        C[i, j] = connected_correlation(i, j, operator, psi, N, S, T=T)
    end
    return C
end

# ============================================================================
# PART 3: ENTANGLEMENT MEASURES
# ============================================================================

"""
    entanglement_spectrum(cut, psi, N, d; n_values=nothing) -> Vector{Float64}

Extract Schmidt spectrum at a bipartition.

Matches TN signature: `entanglement_spectrum(bond, psi; n_values=nothing)`

# Arguments
- `cut::Int`: Bipartition point (sites 1:cut | cut+1:N)
- `psi::AbstractVector`: State vector
- `N::Int`: Number of sites
- `d::Int`: Local Hilbert space dimension
- `n_values::Union{Int,Nothing}`: Number of values to return (all if nothing)

# Returns
Vector of Schmidt values λᵢ in descending order

# Example
```julia
spectrum = entanglement_spectrum(5, psi, 10, 2)
top_10 = entanglement_spectrum(5, psi, 10, 2, n_values=10)
```
"""
function entanglement_spectrum(cut::Int, psi::AbstractVector{<:Number}, 
                                N::Int, d::Int; n_values::Union{Int,Nothing}=nothing)
    @assert 1 <= cut < N "cut must be in [1, N-1]"
    
    D_left = d^cut
    D_right = d^(N - cut)
    
    # Reshape to matrix (left | right)
    psi_mat = reshape(psi, D_left, D_right)
    
    # SVD gives Schmidt decomposition
    sv = svdvals(psi_mat)
    
    # Normalize and filter
    sv = sv ./ norm(sv)
    sv = sv[sv .> 1e-14]
    
    # Sort descending
    sort!(sv, rev=true)
    
    if n_values !== nothing
        n_values = min(n_values, length(sv))
        return sv[1:n_values]
    else
        return sv
    end
end

"""
    entanglement_entropy(cut, psi, N, d; alpha=1) -> Float64

Compute entanglement entropy across a bipartition.

Matches TN signature: `entanglement_entropy(bond, psi; alpha=1)`

- alpha=1: von Neumann entropy S = -Σᵢ λᵢ² log(λᵢ²)
- alpha≠1: Renyi entropy Sₐ = 1/(1-α) log(Σᵢ λᵢ^(2α))

# Arguments
- `cut::Int`: Bipartition point (sites 1:cut | cut+1:N)
- `psi::AbstractVector`: State vector
- `N::Int`: Number of sites
- `d::Int`: Local Hilbert space dimension
- `alpha::Real`: Renyi index (default: 1 for von Neumann)

# Returns
Entanglement entropy (natural log units)

# Example
```julia
S_vn = entanglement_entropy(5, psi, 10, 2)           # von Neumann
S_2 = entanglement_entropy(5, psi, 10, 2, alpha=2)   # Renyi-2
```
"""
function entanglement_entropy(cut::Int, psi::AbstractVector{<:Number}, 
                               N::Int, d::Int; alpha::Real=1)
    @assert alpha > 0 "alpha must be positive"
    
    # Get Schmidt spectrum
    schmidt_values = entanglement_spectrum(cut, psi, N, d)
    
    # Compute entropy
    if alpha ≈ 1
        # von Neumann: S = -Σ λ² log(λ²)
        p = schmidt_values .^ 2
        return -sum(λ * log(λ) for λ in p if λ > 1e-14)
    else
        # Renyi: Sₐ = 1/(1-α) log(Σ λ^(2α))
        p = schmidt_values .^ 2
        return log(sum(λ^alpha for λ in p)) / (1 - alpha)
    end
end

# Convenience alias
const bipartite_entanglement_entropy = entanglement_entropy

"""
    all_entanglement_entropies(psi, N, d; alpha=1) -> Vector{Float64}

Compute entanglement entropy at all cuts.

Matches TN: `all_entanglement_entropies(psi; alpha=1)`

# Returns
Vector of length N-1: [S(1|2:N), S(1:2|3:N), ..., S(1:N-1|N)]
"""
function all_entanglement_entropies(psi::AbstractVector{<:Number}, N::Int, d::Int;
                                     alpha::Real=1)
    return [entanglement_entropy(cut, psi, N, d, alpha=alpha) for cut in 1:N-1]
end

# ============================================================================
# PART 4: ENERGY OBSERVABLES
# ============================================================================

"""
    energy_expectation(psi, H) -> Float64

Compute energy expectation value ⟨ψ|H|ψ⟩.

Matches TN signature: `energy_expectation(psi, ham)`
(TN uses MPO, ED uses sparse matrix)

# Arguments
- `psi::AbstractVector`: State vector
- `H::AbstractMatrix`: Hamiltonian (sparse matrix)

# Example
```julia
H = build_H_spin(N, S, terms)
E = energy_expectation(psi, H)
```
"""
function energy_expectation(psi::AbstractVector{<:Number}, H::AbstractMatrix)
    return real(dot(psi, H * psi))
end

"""
    energy_variance(psi, H) -> Float64

Compute energy variance ⟨H²⟩ - ⟨H⟩².

Matches TN signature: `energy_variance(psi, ham)`

Measures how close state is to eigenstate:
- Variance ≈ 0: Eigenstate
- Variance > 0: Superposition

# Example
```julia
var_E = energy_variance(psi, H)
if var_E < 1e-10
    println("State is an eigenstate!")
end
```
"""
function energy_variance(psi::AbstractVector{<:Number}, H::AbstractMatrix)
    E = energy_expectation(psi, H)
    E2 = real(dot(psi, H * (H * psi)))
    return max(0.0, E2 - E^2)  # Ensure non-negative
end

# ============================================================================
# PART 5: STATE PROPERTIES
# ============================================================================

"""
    inner_product(psi) -> Float64

Compute inner product ⟨ψ|ψ⟩ (norm squared).

Matches TN: `inner_product(psi)`

For normalized state, returns 1.0.
"""
function inner_product(psi::AbstractVector{<:Number})
    return real(dot(psi, psi))
end

"""
    overlap(psi1, psi2) -> ComplexF64

Compute overlap ⟨ψ₁|ψ₂⟩.
"""
function overlap(psi1::AbstractVector{<:Number}, psi2::AbstractVector{<:Number})
    return dot(psi1, psi2)
end

"""
    fidelity(psi1, psi2) -> Float64

Compute fidelity |⟨ψ₁|ψ₂⟩|².
"""
function fidelity(psi1::AbstractVector{<:Number}, psi2::AbstractVector{<:Number})
    return abs2(dot(psi1, psi2))
end

"""
    loschmidt_echo(psi0, psi_t, N) -> Float64

Compute Loschmidt echo -log|⟨ψ(0)|ψ(t)⟩|² / N.
"""
function loschmidt_echo(psi0::AbstractVector{<:Number}, 
                         psi_t::AbstractVector{<:Number}, N::Int)
    F = fidelity(psi0, psi_t)
    return -log(max(F, 1e-300)) / N
end

# ============================================================================
# PART 6: SPIN-BOSON OBSERVABLES
# ============================================================================
#
# Convention: Boson at position 0 (first in tensor product)
# |ψ⟩ = |boson⟩ ⊗ |spin_1⟩ ⊗ |spin_2⟩ ⊗ ... ⊗ |spin_N⟩
#
# All functions have _sb suffix to distinguish from spin-only versions.
# ============================================================================

"""
    single_site_expectation_sb(site, operator, psi, N_spins, nmax, S; T=ComplexF64) -> Float64

Single-site spin expectation in spin-boson system.
"""
function single_site_expectation_sb(site::Int, operator::AbstractMatrix,
                                     psi::AbstractVector{<:Number}, 
                                     N_spins::Int, nmax::Int, S::Real;
                                     T::Type=ComplexF64)
    d_spin = Int(2S + 1)
    d_boson = nmax + 1
    O = embed_spin_op_sb(Matrix{T}(operator), site, N_spins, d_spin, d_boson, T=T)
    return real(dot(psi, O * psi))
end

function single_site_expectation_sb(site::Int, op::Symbol,
                                     psi::AbstractVector{<:Number},
                                     N_spins::Int, nmax::Int, S::Real;
                                     T::Type=ComplexF64)
    ops = spin_matrices(S, T=T)
    return single_site_expectation_sb(site, ops[op], psi, N_spins, nmax, S, T=T)
end

# Alias for runner compatibility
const spinboson_local_spin_expectation = single_site_expectation_sb

"""
    expectation_value_all_sites_sb(operator, psi, N_spins, nmax, S; T=ComplexF64) -> Vector{Float64}

Local spin expectation on all spin sites in spin-boson system.
"""
function expectation_value_all_sites_sb(operator, psi::AbstractVector{<:Number},
                                         N_spins::Int, nmax::Int, S::Real;
                                         T::Type=ComplexF64)
    return [single_site_expectation_sb(i, operator, psi, N_spins, nmax, S, T=T) 
            for i in 1:N_spins]
end

# Alias
const spinboson_expectation_all_sites = expectation_value_all_sites_sb

"""
    subsystem_expectation_sum_sb(operator, psi, l, m, N_spins, nmax, S; T=ComplexF64) -> Float64

Sum of spin expectations over subsystem in spin-boson system.
"""
function subsystem_expectation_sum_sb(operator::AbstractMatrix,
                                       psi::AbstractVector{<:Number},
                                       l::Int, m::Int,
                                       N_spins::Int, nmax::Int, S::Real;
                                       T::Type=ComplexF64)
    @assert 1 ≤ l ≤ m ≤ N_spins "Invalid range"
    
    d_spin = Int(2S + 1)
    d_boson = nmax + 1
    D = d_boson * d_spin^N_spins
    
    O_total = spzeros(T, D, D)
    for i in l:m
        O_total += embed_spin_op_sb(Matrix{T}(operator), i, N_spins, d_spin, d_boson, T=T)
    end
    
    return real(dot(psi, O_total * psi))
end

function subsystem_expectation_sum_sb(op::Symbol, psi::AbstractVector{<:Number},
                                       l::Int, m::Int,
                                       N_spins::Int, nmax::Int, S::Real;
                                       T::Type=ComplexF64)
    ops = spin_matrices(S, T=T)
    return subsystem_expectation_sum_sb(ops[op], psi, l, m, N_spins, nmax, S, T=T)
end

"""
    total_magnetization_sb(psi, N_spins, nmax, S, direction=:Z; T=ComplexF64) -> Float64

Total spin in spin-boson system.
"""
function total_magnetization_sb(psi::AbstractVector{<:Number}, 
                                 N_spins::Int, nmax::Int, S::Real,
                                 direction::Symbol=:Z; T::Type=ComplexF64)
    return subsystem_expectation_sum_sb(direction, psi, 1, N_spins, N_spins, nmax, S, T=T)
end

# Alias
const spinboson_total_magnetization = total_magnetization_sb

"""
    two_site_expectation_sb(site_i, op_i, site_j, op_j, psi, N_spins, nmax, S; T=ComplexF64) -> Float64

Two-site spin expectation in spin-boson system.
"""
function two_site_expectation_sb(site_i::Int, op_i::AbstractMatrix,
                                  site_j::Int, op_j::AbstractMatrix,
                                  psi::AbstractVector{<:Number},
                                  N_spins::Int, nmax::Int, S::Real;
                                  T::Type=ComplexF64)
    d_spin = Int(2S + 1)
    d_boson = nmax + 1
    
    if site_i == site_j
        O = embed_spin_op_sb(Matrix{T}(op_i * op_j), site_i, N_spins, d_spin, d_boson, T=T)
    else
        O = embed_two_spin_ops_sb(Matrix{T}(op_i), Matrix{T}(op_j), site_i, site_j, 
                                   N_spins, d_spin, d_boson, T=T)
    end
    
    return real(dot(psi, O * psi))
end

function two_site_expectation_sb(site_i::Int, op_i::Symbol,
                                  site_j::Int, op_j::Symbol,
                                  psi::AbstractVector{<:Number},
                                  N_spins::Int, nmax::Int, S::Real;
                                  T::Type=ComplexF64)
    ops = spin_matrices(S, T=T)
    return two_site_expectation_sb(site_i, ops[op_i], site_j, ops[op_j], 
                                    psi, N_spins, nmax, S, T=T)
end

"""
    correlation_function_sb(site_i, site_j, operator, psi, N_spins, nmax, S; T=ComplexF64) -> Float64

Spin-spin correlation in spin-boson system.
"""
function correlation_function_sb(site_i::Int, site_j::Int, operator,
                                  psi::AbstractVector{<:Number},
                                  N_spins::Int, nmax::Int, S::Real;
                                  T::Type=ComplexF64)
    return two_site_expectation_sb(site_i, operator, site_j, operator, 
                                    psi, N_spins, nmax, S, T=T)
end

# Alias
const spinboson_two_point_correlation = correlation_function_sb

"""
    connected_correlation_sb(site_i, site_j, operator, psi, N_spins, nmax, S; T=ComplexF64) -> Float64

Connected spin-spin correlation in spin-boson system.
"""
function connected_correlation_sb(site_i::Int, site_j::Int, operator,
                                   psi::AbstractVector{<:Number},
                                   N_spins::Int, nmax::Int, S::Real;
                                   T::Type=ComplexF64)
    corr = correlation_function_sb(site_i, site_j, operator, psi, N_spins, nmax, S, T=T)
    exp_i = single_site_expectation_sb(site_i, operator, psi, N_spins, nmax, S, T=T)
    exp_j = single_site_expectation_sb(site_j, operator, psi, N_spins, nmax, S, T=T)
    return corr - exp_i * exp_j
end

"""
    correlation_matrix_sb(operator, psi, N_spins, nmax, S; T=ComplexF64) -> Matrix{Float64}

Full spin-spin correlation matrix in spin-boson system.
"""
function correlation_matrix_sb(operator, psi::AbstractVector{<:Number},
                                N_spins::Int, nmax::Int, S::Real;
                                T::Type=ComplexF64)
    C = zeros(Float64, N_spins, N_spins)
    for i in 1:N_spins, j in 1:N_spins
        C[i, j] = correlation_function_sb(i, j, operator, psi, N_spins, nmax, S, T=T)
    end
    return C
end

# Alias
const spinboson_correlation_matrix = correlation_matrix_sb

# ============================================================================
# PART 7: BOSON-SPECIFIC OBSERVABLES
# ============================================================================

"""
    boson_number(psi, N_spins, nmax, S=0.5; T=ComplexF64) -> Float64

Measure boson occupation ⟨b†b⟩.
"""
function boson_number(psi::AbstractVector{<:Number}, N_spins::Int, nmax::Int,
                       S::Real=0.5; T::Type=ComplexF64)
    d_spin = Int(2S + 1)
    d_boson = nmax + 1
    bos_ops = boson_matrices(nmax, T=T)
    O = embed_boson_op_sb(bos_ops[:Bn], N_spins, d_spin, d_boson, T=T)
    return real(dot(psi, O * psi))
end

# Alias
const boson_number_expectation = boson_number

"""
    boson_distribution(psi, N_spins, nmax, S=0.5) -> Vector{Float64}

Compute photon number distribution P(n) = |⟨n|ψ⟩|².

# Returns
Vector of length nmax+1: [P(0), P(1), ..., P(nmax)]
"""
function boson_distribution(psi::AbstractVector{<:Number}, N_spins::Int, nmax::Int,
                             S::Real=0.5)
    d_spin = Int(2S + 1)
    d_boson = nmax + 1
    D_spin = d_spin^N_spins
    
    # Reshape: |ψ⟩ = Σₙ |n⟩ ⊗ |ψ_spin(n)⟩
    psi_mat = reshape(psi, d_boson, D_spin)
    
    # P(n) = ∥|ψ_spin(n)⟩∥²
    P = [sum(abs2.(psi_mat[n+1, :])) for n in 0:nmax]
    
    return P
end

# Alias
const boson_number_distribution = boson_distribution

"""
    boson_field_expectation(psi, N_spins, nmax, S=0.5; T=ComplexF64) -> ComplexF64

Measure boson field ⟨b⟩ (for coherent state analysis).
"""
function boson_field_expectation(psi::AbstractVector{<:Number}, N_spins::Int, nmax::Int,
                                  S::Real=0.5; T::Type=ComplexF64)
    d_spin = Int(2S + 1)
    d_boson = nmax + 1
    bos_ops = boson_matrices(nmax, T=T)
    O = embed_boson_op_sb(bos_ops[:a], N_spins, d_spin, d_boson, T=T)
    return dot(psi, O * psi)
end

# ============================================================================
# PART 8: SPIN-BOSON ENTANGLEMENT
# ============================================================================

"""
    entanglement_spectrum_sb(cut, psi, N_spins, d_spin, d_boson; n_values=nothing) -> Vector{Float64}

Schmidt spectrum for spin-boson system.
Cut is in the spin chain (boson always on left).

# Arguments
- `cut::Int`: Cut in spin chain (spins 1:cut on left with boson)
"""
function entanglement_spectrum_sb(cut::Int, psi::AbstractVector{<:Number},
                                   N_spins::Int, d_spin::Int, d_boson::Int;
                                   n_values::Union{Int,Nothing}=nothing)
    @assert 1 <= cut < N_spins "cut must be in [1, N_spins-1]"
    
    D_left = d_boson * d_spin^cut
    D_right = d_spin^(N_spins - cut)
    
    psi_mat = reshape(psi, D_left, D_right)
    sv = svdvals(psi_mat)
    sv = sv ./ norm(sv)
    sv = sv[sv .> 1e-14]
    sort!(sv, rev=true)
    
    if n_values !== nothing
        n_values = min(n_values, length(sv))
        return sv[1:n_values]
    else
        return sv
    end
end

# Alias
const spinboson_entanglement_spectrum = entanglement_spectrum_sb

"""
    entanglement_entropy_sb(cut, psi, N_spins, d_spin, d_boson; alpha=1) -> Float64

Entanglement entropy for spin-boson system.
"""
function entanglement_entropy_sb(cut::Int, psi::AbstractVector{<:Number},
                                  N_spins::Int, d_spin::Int, d_boson::Int;
                                  alpha::Real=1)
    @assert alpha > 0 "alpha must be positive"
    
    schmidt_values = entanglement_spectrum_sb(cut, psi, N_spins, d_spin, d_boson)
    
    if alpha ≈ 1
        p = schmidt_values .^ 2
        return -sum(λ * log(λ) for λ in p if λ > 1e-14)
    else
        p = schmidt_values .^ 2
        return log(sum(λ^alpha for λ in p)) / (1 - alpha)
    end
end

# Alias
const spinboson_entanglement_entropy = entanglement_entropy_sb

"""
    all_entanglement_entropies_sb(psi, N_spins, d_spin, d_boson; alpha=1) -> Vector{Float64}

Entanglement entropy at all cuts in spin-boson system.
"""
function all_entanglement_entropies_sb(psi::AbstractVector{<:Number},
                                        N_spins::Int, d_spin::Int, d_boson::Int;
                                        alpha::Real=1)
    return [entanglement_entropy_sb(cut, psi, N_spins, d_spin, d_boson, alpha=alpha) 
            for cut in 1:N_spins-1]
end

# ============================================================================
# PART 9: BOSON-SPIN ENTANGLEMENT
# ============================================================================

"""
    boson_spin_entanglement(psi, N_spins, d_spin, d_boson; alpha=1) -> Float64

Entanglement entropy between boson and all spins.
"""
function boson_spin_entanglement(psi::AbstractVector{<:Number},
                                  N_spins::Int, d_spin::Int, d_boson::Int;
                                  alpha::Real=1)
    D_spin = d_spin^N_spins
    
    # Reshape: boson | spins
    psi_mat = reshape(psi, d_boson, D_spin)
    sv = svdvals(psi_mat)
    sv = sv ./ norm(sv)
    sv = sv[sv .> 1e-14]
    
    if alpha ≈ 1
        p = sv .^ 2
        return -sum(λ * log(λ) for λ in p if λ > 1e-14)
    else
        p = sv .^ 2
        return log(sum(λ^alpha for λ in p)) / (1 - alpha)
    end
end

# ============================================================================
# PART 10: ALIASES FOR RUNNER COMPATIBILITY
# ============================================================================
#
# These aliases ensure the observable runner works without modification.
# The runner uses some alternative names that we map here.
# ============================================================================

# Runner uses these names (from _calculate_ed_observable):
const local_expectation = single_site_expectation
const spinboson_local_expectation = single_site_expectation_sb

# ============================================================================
# PART 11: CONFIG-BASED INTERFACE
# ============================================================================

"""
    measure_observables(psi, config) -> Dict

Measure observables based on configuration dict.

# Config structure
```json
{
    "system": {"type": "spin", "N": 10, "S": 0.5},
    "observables": {
        "local": [{"op": "Z", "sites": [1, 2, 3]}],
        "correlation": [{"op": "Z", "pairs": [[1,2], [1,3]]}],
        "entanglement": {"cuts": [5]}
    }
}
```
"""
function measure_observables(psi::AbstractVector{<:Number}, config::Dict)
    system = config["system"]
    obs_config = get(config, "observables", Dict())
    
    system_type = system["type"]
    S = get(system, "S", 0.5)
    results = Dict{String, Any}()
    
    if system_type == "spin"
        N = system["N"]
        d = Int(2S + 1)
        
        # Local observables
        if haskey(obs_config, "local")
            results["local"] = Dict{String, Any}()
            for obs in obs_config["local"]
                op = Symbol(obs["op"])
                sites = get(obs, "sites", 1:N)
                key = "$(op)_profile"
                results["local"][key] = [single_site_expectation(i, op, psi, N, S) 
                                          for i in sites]
            end
        end
        
        # Correlations
        if haskey(obs_config, "correlation")
            results["correlation"] = Dict{String, Any}()
            for obs in obs_config["correlation"]
                op = Symbol(obs["op"])
                if haskey(obs, "pairs")
                    pairs = obs["pairs"]
                    key = "$(op)$(op)_pairs"
                    results["correlation"][key] = [correlation_function(p[1], p[2], op, psi, N, S) 
                                                    for p in pairs]
                else
                    key = "$(op)$(op)_matrix"
                    results["correlation"][key] = correlation_matrix(op, psi, N, S)
                end
            end
        end
        
        # Entanglement
        if haskey(obs_config, "entanglement")
            cuts = get(obs_config["entanglement"], "cuts", [N ÷ 2])
            results["entanglement"] = [entanglement_entropy(c, psi, N, d) for c in cuts]
        end
        
    elseif system_type == "spinboson"
        N_spins = system["N_spins"]
        nmax = system["nmax"]
        d_spin = Int(2S + 1)
        d_boson = nmax + 1
        
        # Local spin observables
        if haskey(obs_config, "local")
            results["local"] = Dict{String, Any}()
            for obs in obs_config["local"]
                op = Symbol(obs["op"])
                sites = get(obs, "sites", 1:N_spins)
                key = "$(op)_profile"
                results["local"][key] = [single_site_expectation_sb(i, op, psi, N_spins, nmax, S) 
                                          for i in sites]
            end
        end
        
        # Boson number
        results["boson_number"] = boson_number(psi, N_spins, nmax, S)
        
        # Correlations
        if haskey(obs_config, "correlation")
            results["correlation"] = Dict{String, Any}()
            for obs in obs_config["correlation"]
                op = Symbol(obs["op"])
                if haskey(obs, "pairs")
                    pairs = obs["pairs"]
                    key = "$(op)$(op)_pairs"
                    results["correlation"][key] = [correlation_function_sb(p[1], p[2], op, psi, N_spins, nmax, S) 
                                                    for p in pairs]
                end
            end
        end
        
        # Entanglement
        if haskey(obs_config, "entanglement")
            cuts = get(obs_config["entanglement"], "cuts", [N_spins ÷ 2])
            results["entanglement"] = [entanglement_entropy_sb(c, psi, N_spins, d_spin, d_boson) 
                                        for c in cuts]
        end
    end
    
    return results
end