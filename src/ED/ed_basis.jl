# ============================================================================
# ED BASIS - Hilbert Space Embedding
# ============================================================================
#
# Provides functions to embed local operators into full Hilbert space.
# This is the core machinery that builds many-body operators from local ones.
#
# STRUCTURE:
#   Spin-only:    |ψ⟩ = |s₁⟩ ⊗ |s₂⟩ ⊗ ... ⊗ |sₙ⟩
#   Spin-boson:   |ψ⟩ = |b⟩ ⊗ |s₁⟩ ⊗ |s₂⟩ ⊗ ... ⊗ |sₙ⟩
#
# USAGE:
#   # Single-site operator
#   Sz_3 = embed_operator(Sz, 3, N, d)
#
#   # Two-site operator  
#   Sz_i_Sz_j = embed_two_site(Sz, Sz, i, j, N, d)
#
# ============================================================================

using LinearAlgebra
using SparseArrays

# ============================================================================
# PART 1: HILBERT SPACE DIMENSIONS
# ============================================================================

"""
    hilbert_dim_spin(N, S) -> Int

Total Hilbert space dimension for N spin-S sites.
"""
function hilbert_dim_spin(N::Int, S::Real)
    d = Int(2S + 1)
    return d^N
end

"""
    hilbert_dim_spinboson(N_spins, S, nmax) -> Int

Total Hilbert space dimension for spin-boson system.
Boson (dim = nmax+1) coupled to N_spins spin-S sites.
"""
function hilbert_dim_spinboson(N_spins::Int, S::Real, nmax::Int)
    d_spin = Int(2S + 1)
    d_boson = nmax + 1
    return d_boson * d_spin^N_spins
end

# ============================================================================
# PART 2: SPIN-ONLY EMBEDDING
# ============================================================================

"""
    embed_operator(op, site, N, d; T=ComplexF64) -> SparseMatrixCSC

Embed single-site operator into N-site Hilbert space.

Creates: I ⊗ ... ⊗ I ⊗ op ⊗ I ⊗ ... ⊗ I
                      ↑
                    site

# Arguments
- `op`: Local operator (d × d matrix)
- `site::Int`: Site index (1 to N)
- `N::Int`: Total number of sites
- `d::Int`: Local Hilbert space dimension

# Returns
Sparse matrix of dimension (d^N × d^N)

# Example
```julia
ops = spin_matrices(0.5)
Sz = ops[:Z]
Sz_3 = embed_operator(Sz, 3, 10, 2)  # σᶻ on site 3 of 10-site chain
```
"""
function embed_operator(op::AbstractMatrix, site::Int, N::Int, d::Int; 
                        T::Type=ComplexF64)
    @assert 1 <= site <= N "Site $site out of range [1, $N]"
    @assert size(op) == (d, d) "Operator size $(size(op)) doesn't match local dim $d"
    
    D = d^N
    
    # Build using kronecker products
    # op_embedded = I_{d^{site-1}} ⊗ op ⊗ I_{d^{N-site}}
    
    d_left = d^(site - 1)
    d_right = d^(N - site)
    
    I_left = sparse(one(T) * I, d_left, d_left)
    I_right = sparse(one(T) * I, d_right, d_right)
    op_sparse = sparse(T.(op))
    
    # kron is left-associative: kron(A, B, C) = kron(kron(A, B), C)
    if site == 1
        result = kron(op_sparse, I_right)
    elseif site == N
        result = kron(I_left, op_sparse)
    else
        result = kron(kron(I_left, op_sparse), I_right)
    end
    
    return result
end

"""
    embed_two_site(op1, op2, i, j, N, d; T=ComplexF64) -> SparseMatrixCSC

Embed two-site operator op1_i ⊗ op2_j into N-site Hilbert space.

# Arguments
- `op1`: Operator on site i
- `op2`: Operator on site j
- `i::Int`: First site index
- `j::Int`: Second site index
- `N::Int`: Total number of sites
- `d::Int`: Local Hilbert space dimension

# Returns
Sparse matrix representing op1_i × op2_j

# Example
```julia
ops = spin_matrices(0.5)
Sz = ops[:Z]
Sz_i_Sz_j = embed_two_site(Sz, Sz, 2, 5, 10, 2)  # σᶻ₂σᶻ₅
```
"""
function embed_two_site(op1::AbstractMatrix, op2::AbstractMatrix, 
                        i::Int, j::Int, N::Int, d::Int; T::Type=ComplexF64)
    @assert 1 <= i <= N "Site i=$i out of range [1, $N]"
    @assert 1 <= j <= N "Site j=$j out of range [1, $N]"
    @assert i != j "Sites must be different (got i=$i, j=$j)"
    
    # Product of two single-site embeddings
    # op1_i × op2_j = (I⊗...⊗op1⊗...⊗I) × (I⊗...⊗op2⊗...⊗I)
    
    O1 = embed_operator(op1, i, N, d, T=T)
    O2 = embed_operator(op2, j, N, d, T=T)
    
    return O1 * O2
end

# ============================================================================
# PART 3: SPIN-BOSON EMBEDDING
# ============================================================================
#
# Convention: Boson is at position 0 (first in tensor product)
# |ψ⟩ = |boson⟩ ⊗ |spin_1⟩ ⊗ |spin_2⟩ ⊗ ... ⊗ |spin_N⟩
#
# Total dimension: d_boson × d_spin^N_spins
# ============================================================================

"""
    embed_spin_op_sb(op, spin_site, N_spins, d_spin, d_boson; T=ComplexF64) -> SparseMatrixCSC

Embed spin operator into spin-boson Hilbert space.

Structure: I_boson ⊗ (spin embedding)

# Arguments
- `op`: Spin operator
- `spin_site::Int`: Spin site index (1 to N_spins)
- `N_spins::Int`: Number of spin sites
- `d_spin::Int`: Spin local dimension
- `d_boson::Int`: Boson local dimension (nmax + 1)

# Example
```julia
# σᶻ on spin site 3 in system with 1 boson + 5 spins
Sz_3 = embed_spin_op_sb(Sz, 3, 5, 2, 5)
```
"""
function embed_spin_op_sb(op::AbstractMatrix, spin_site::Int, 
                          N_spins::Int, d_spin::Int, d_boson::Int; 
                          T::Type=ComplexF64)
    @assert 1 <= spin_site <= N_spins "Spin site $spin_site out of range [1, $N_spins]"
    @assert size(op) == (d_spin, d_spin) "Operator size doesn't match spin dim"
    
    # First: embed in pure spin space
    op_spin_space = embed_operator(op, spin_site, N_spins, d_spin, T=T)
    
    # Then: tensor with boson identity
    I_boson = sparse(one(T) * I, d_boson, d_boson)
    
    return kron(I_boson, op_spin_space)
end

"""
    embed_boson_op_sb(op, N_spins, d_spin, d_boson; T=ComplexF64) -> SparseMatrixCSC

Embed boson operator into spin-boson Hilbert space.

Structure: op_boson ⊗ I_spins

# Arguments
- `op`: Boson operator
- `N_spins::Int`: Number of spin sites
- `d_spin::Int`: Spin local dimension
- `d_boson::Int`: Boson local dimension

# Example
```julia
# Number operator in system with 1 boson + 5 spins
Bn = embed_boson_op_sb(boson_ops[:Bn], 5, 2, 5)
```
"""
function embed_boson_op_sb(op::AbstractMatrix, N_spins::Int, 
                           d_spin::Int, d_boson::Int; T::Type=ComplexF64)
    @assert size(op) == (d_boson, d_boson) "Operator size doesn't match boson dim"
    
    # Boson op ⊗ Identity on all spins
    D_spins = d_spin^N_spins
    I_spins = sparse(one(T) * I, D_spins, D_spins)
    op_sparse = sparse(T.(op))
    
    return kron(op_sparse, I_spins)
end

"""
    embed_two_spin_ops_sb(op1, op2, i, j, N_spins, d_spin, d_boson; T=ComplexF64) -> SparseMatrixCSC

Embed two-spin operator into spin-boson Hilbert space.

Structure: I_boson ⊗ (op1_i × op2_j in spin space)

# Arguments
- `op1`: Spin operator on site i
- `op2`: Spin operator on site j
- `i::Int`: First spin site
- `j::Int`: Second spin site
- `N_spins::Int`: Number of spin sites
- `d_spin::Int`: Spin local dimension
- `d_boson::Int`: Boson local dimension

# Example
```julia
# σᶻᵢσᶻⱼ in spin-boson system
ZZ_ij = embed_two_spin_ops_sb(Sz, Sz, 2, 4, 5, 2, 5)
```
"""
function embed_two_spin_ops_sb(op1::AbstractMatrix, op2::AbstractMatrix,
                               i::Int, j::Int, N_spins::Int, 
                               d_spin::Int, d_boson::Int; T::Type=ComplexF64)
    @assert 1 <= i <= N_spins "Site i=$i out of range [1, $N_spins]"
    @assert 1 <= j <= N_spins "Site j=$j out of range [1, $N_spins]"
    @assert i != j "Sites must be different"
    
    # Two-spin operator in pure spin space
    op_spin_space = embed_two_site(op1, op2, i, j, N_spins, d_spin, T=T)
    
    # Tensor with boson identity
    I_boson = sparse(one(T) * I, d_boson, d_boson)
    
    return kron(I_boson, op_spin_space)
end

"""
    embed_spinboson_coupling(bos_op, spin_op, spin_site, N_spins, d_spin, d_boson; T=ComplexF64) -> SparseMatrixCSC

Embed spin-boson coupling term: bos_op ⊗ spin_op_i

For collective coupling (bos_op ⊗ Σᵢ spin_opᵢ), call this for each site and sum.

# Arguments
- `bos_op`: Boson operator
- `spin_op`: Spin operator
- `spin_site::Int`: Spin site index
- `N_spins::Int`: Number of spin sites
- `d_spin::Int`: Spin local dimension
- `d_boson::Int`: Boson local dimension

# Example
```julia
# g × a × σˣ₃ (single site coupling)
coupling = embed_spinboson_coupling(a, Sx, 3, 5, 2, 5)

# g × a × Σᵢσˣᵢ (collective coupling)
collective = sum(embed_spinboson_coupling(a, Sx, i, 5, 2, 5) for i in 1:5)
```
"""
function embed_spinboson_coupling(bos_op::AbstractMatrix, spin_op::AbstractMatrix,
                                  spin_site::Int, N_spins::Int, 
                                  d_spin::Int, d_boson::Int; T::Type=ComplexF64)
    @assert 1 <= spin_site <= N_spins "Spin site $spin_site out of range [1, $N_spins]"
    @assert size(bos_op) == (d_boson, d_boson) "Boson op size mismatch"
    @assert size(spin_op) == (d_spin, d_spin) "Spin op size mismatch"
    
    # Embed spin operator in spin-only space
    spin_embedded = embed_operator(spin_op, spin_site, N_spins, d_spin, T=T)
    
    # Tensor product: bos_op ⊗ spin_embedded
    bos_sparse = sparse(T.(bos_op))
    
    return kron(bos_sparse, spin_embedded)
end

# ============================================================================
# PART 4: COLLECTIVE OPERATORS
# ============================================================================

"""
    collective_spin_op(op, N, d; T=ComplexF64) -> SparseMatrixCSC

Build collective spin operator: Σᵢ opᵢ

# Example
```julia
# Total Sz = Σᵢ σᶻᵢ
Sz_total = collective_spin_op(Sz, 10, 2)
```
"""
function collective_spin_op(op::AbstractMatrix, N::Int, d::Int; T::Type=ComplexF64)
    D = d^N
    result = spzeros(T, D, D)
    
    for i in 1:N
        result += embed_operator(op, i, N, d, T=T)
    end
    
    return result
end

"""
    collective_spin_op_sb(op, N_spins, d_spin, d_boson; T=ComplexF64) -> SparseMatrixCSC

Build collective spin operator in spin-boson space: I_boson ⊗ Σᵢ opᵢ

# Example
```julia
# Total Sx in spin-boson system
Sx_total = collective_spin_op_sb(Sx, 5, 2, 5)
```
"""
function collective_spin_op_sb(op::AbstractMatrix, N_spins::Int, 
                               d_spin::Int, d_boson::Int; T::Type=ComplexF64)
    D = d_boson * d_spin^N_spins
    result = spzeros(T, D, D)
    
    for i in 1:N_spins
        result += embed_spin_op_sb(op, i, N_spins, d_spin, d_boson, T=T)
    end
    
    return result
end

# ============================================================================
# PART 5: UTILITY FUNCTIONS
# ============================================================================

"""
    check_hermitian(H::AbstractMatrix; tol=1e-10) -> Bool

Check if matrix is Hermitian within tolerance.
"""
function check_hermitian(H::AbstractMatrix; tol::Float64=1e-10)
    return norm(H - H') < tol * max(1.0, norm(H))
end

"""
    make_hermitian(H::AbstractMatrix) -> AbstractMatrix

Force matrix to be exactly Hermitian: (H + H†)/2
"""
function make_hermitian(H::AbstractMatrix)
    return (H + H') / 2
end

"""
    sparsity(H::SparseMatrixCSC) -> Float64

Return fraction of zero elements.
"""
function sparsity(H::SparseMatrixCSC)
    return 1.0 - nnz(H) / length(H)
end

"""
    memory_estimate_MB(N, d; T=ComplexF64) -> Float64

Estimate memory for dense matrix in MB.
"""
function memory_estimate_MB(N::Int, d::Int; T::Type=ComplexF64)
    D = d^N
    bytes = D^2 * sizeof(T)
    return bytes / (1024^2)
end

"""
    memory_estimate_sparse_MB(H::SparseMatrixCSC) -> Float64

Actual memory usage of sparse matrix in MB.
"""
function memory_estimate_sparse_MB(H::SparseMatrixCSC)
    # CSC format: values + row indices + column pointers
    bytes = sizeof(H.nzval) + sizeof(H.rowval) + sizeof(H.colptr)
    return bytes / (1024^2)
end
