# ============================================================================
# ED HAMILTONIAN - General Hamiltonian Builder
# ============================================================================
#
# Builds Hamiltonian matrices from EDTerm specifications.
# Equivalent to Builders/mpobuilder.jl in TN.
#
# FLOW:
#   TN:  Channels → FSM → build_mpo() → MPO
#   ED:  Terms → build_H_spin() / build_H_spinboson() → Sparse Matrix
#
# ============================================================================

using LinearAlgebra
using SparseArrays

# ————————————————————————————————————————————————————————————————
# 1) Pure-spin Hamiltonian
# ————————————————————————————————————————————————————————————————
function build_H_spin(
    N::Integer,
    S::Real,
    terms::Vector{<:EDTerm};
    T::Type = ComplexF64,
)
    d = Int(2S + 1)
    D = d^N
    ops = spin_matrices(S, T=T)
    
    H = spzeros(T, D, D)
    
    for term in terms
        if term isa EDField
            for i in 1:N
                H += term.strength * embed_operator(ops[term.op], i, N, d, T=T)
            end
            
        elseif term isa EDCoupling
            for i in 1:N, j in 1:N
                if i != j
                    c = term.coeff(i, j, N)
                    if abs(c) > 1e-15
                        H += c * embed_two_site(ops[term.op1], ops[term.op2], i, j, N, d, T=T)
                    end
                end
            end
        end
    end
    
    return H
end

# ————————————————————————————————————————————————————————————————
# 2) Spin-boson Hamiltonian
# ————————————————————————————————————————————————————————————————
function build_H_spinboson(
    N_spins::Integer,
    nmax::Integer,
    S::Real,
    terms::Vector{<:EDTerm};
    T::Type = ComplexF64,
)
    d_spin = Int(2S + 1)
    d_boson = nmax + 1
    D = d_boson * d_spin^N_spins
    
    spin_ops = spin_matrices(S, T=T)
    bos_ops = boson_matrices(nmax, T=T)
    
    H = spzeros(T, D, D)
    
    for term in terms
        if term isa EDField
            for i in 1:N_spins
                H += term.strength * embed_spin_op_sb(spin_ops[term.op], i, 
                                                       N_spins, d_spin, d_boson, T=T)
            end
            
        elseif term isa EDCoupling
            for i in 1:N_spins, j in 1:N_spins
                if i != j
                    c = term.coeff(i, j, N_spins)
                    if abs(c) > 1e-15
                        H += c * embed_two_spin_ops_sb(spin_ops[term.op1], spin_ops[term.op2],
                                                        i, j, N_spins, d_spin, d_boson, T=T)
                    end
                end
            end
            
        elseif term isa EDBosonTerm
            H += term.strength * embed_boson_op_sb(bos_ops[term.op], N_spins, 
                                                    d_spin, d_boson, T=T)
            
        elseif term isa EDSpinBosonCoupling
            for i in 1:N_spins
                H += term.strength * embed_spinboson_coupling(bos_ops[term.boson_op],
                                                               spin_ops[term.spin_op], i,
                                                               N_spins, d_spin, d_boson, T=T)
            end
        end
    end
    
    return H
end