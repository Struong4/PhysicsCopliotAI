# ============================================================================
# ED SOLVER - Eigensolvers and Time Evolution
# ============================================================================
#
# Provides eigensolvers and time evolution for exact diagonalization.
#
# TASKS:
#   - ed_ground_state: Ground state only
#   - ed_spectrum: Multiple eigenstates
#   - ed_time_evolution: Step-wise time evolution (parallel to TDVP)
#
# TIME EVOLUTION DESIGN:
#   - prepare_time_evolution(): Diagonalize once (expensive)
#   - evolve_to_time(): Get psi(t) (cheap, just phase factors)
#   - Step-wise saving matches TDVP for unified user experience
#
# ============================================================================

using LinearAlgebra
using SparseArrays
using Arpack

# ============================================================================
# PART 1: GROUND STATE SOLVER
# ============================================================================

"""
    solve_ground_state(H; use_sparse=true, tol=1e-10, maxiter=300) -> (E0, psi0)

Compute ground state energy and wavefunction.

# Arguments
- `H`: Hamiltonian matrix (sparse or dense)
- `use_sparse::Bool`: Use sparse solver (Arpack) if true
- `tol::Float64`: Convergence tolerance for sparse solver
- `maxiter::Int`: Max iterations for sparse solver

# Returns
- `E0::Float64`: Ground state energy
- `psi0::Vector`: Ground state wavefunction (normalized)

# Example
```julia
H = build_H_spin(10, 0.5, terms)
E0, psi0 = solve_ground_state(H)
```
"""
function solve_ground_state(H::AbstractMatrix; 
                            use_sparse::Bool=true,
                            tol::Float64=1e-10,
                            maxiter::Int=300)
    D = size(H, 1)
    
    if use_sparse && issparse(H) && D > 20
        vals, vecs, info = eigs(H, nev=1, which=:SR, tol=tol, maxiter=maxiter)
        
        if info != 0
            @warn "Arpack did not fully converge (info=$info)"
        end
        
        E0 = real(vals[1])
        psi0 = vecs[:, 1]
    else
        H_dense = Matrix(Hermitian(H))
        eig = eigen(H_dense)
        
        idx = argmin(real(eig.values))
        E0 = real(eig.values[idx])
        psi0 = eig.vectors[:, idx]
    end
    
    psi0 = psi0 / norm(psi0)
    
    return E0, psi0
end

# ============================================================================
# PART 2: SPECTRUM SOLVER
# ============================================================================

"""
    solve_spectrum(H, n_states; use_sparse=true, tol=1e-10, maxiter=300) -> (energies, states)

Compute lowest n_states eigenvalues and eigenvectors.

# Arguments
- `H`: Hamiltonian matrix
- `n_states::Int`: Number of states to compute
- `use_sparse::Bool`: Use sparse solver if true
- `tol::Float64`: Convergence tolerance for sparse solver
- `maxiter::Int`: Max iterations for sparse solver

# Returns
- `energies::Vector{Float64}`: Eigenvalues (ascending order)
- `states::Matrix`: Eigenvectors as columns

# Example
```julia
H = build_H_spin(10, 0.5, terms)
energies, states = solve_spectrum(H, 5)
E0 = energies[1]       # Ground state energy
E1 = energies[2]       # First excited state
gap = E1 - E0          # Spectral gap
```
"""
function solve_spectrum(H::AbstractMatrix, n_states::Int;
                        use_sparse::Bool=true,
                        tol::Float64=1e-10,
                        maxiter::Int=300)
    D = size(H, 1)
    
    @assert n_states >= 1 "n_states must be at least 1"
    @assert n_states <= D "n_states cannot exceed Hilbert space dimension $D"
    
    if use_sparse && issparse(H) && D > 20 && n_states < D ÷ 2
        vals, vecs, info = eigs(H, nev=n_states, which=:SR, tol=tol, maxiter=maxiter)
        
        if info != 0
            @warn "Arpack did not fully converge (info=$info)"
        end
        
        idx = sortperm(real(vals))
        energies = real(vals[idx])
        states = vecs[:, idx]
    else
        H_dense = Matrix(Hermitian(H))
        eig = eigen(H_dense)
        
        idx = sortperm(real(eig.values))
        energies = real(eig.values[idx[1:n_states]])
        states = eig.vectors[:, idx[1:n_states]]
    end
    
    for i in 1:n_states
        states[:, i] = states[:, i] / norm(states[:, i])
    end
    
    return energies, states
end

"""
    solve_full_spectrum(H) -> (energies, states)

Compute complete spectrum (all eigenvalues and eigenvectors).
Warning: Expensive for large systems. Use only for small Hilbert spaces.

# Arguments
- `H`: Hamiltonian matrix

# Returns
- `energies::Vector{Float64}`: All eigenvalues (ascending order)
- `states::Matrix`: All eigenvectors as columns

# Example
```julia
H = build_H_spin(8, 0.5, terms)  # D = 256, manageable
energies, states = solve_full_spectrum(H)
```
"""
function solve_full_spectrum(H::AbstractMatrix)
    D = size(H, 1)
    
    if D > 4096
        @warn "Full spectrum for D=$D will be expensive"
    end
    
    H_dense = Matrix(Hermitian(H))
    eig = eigen(H_dense)
    
    idx = sortperm(real(eig.values))
    energies = real(eig.values[idx])
    states = eig.vectors[:, idx]
    
    return energies, states
end

# ============================================================================
# PART 3: TIME EVOLUTION - PREPARATION
# ============================================================================

"""
    TimeEvolutionSetup

Container holding precomputed data for efficient time evolution.
Created once by prepare_time_evolution(), used many times by evolve_to_time().

# Fields
- `energies`: Eigenvalues of H
- `eigenstates`: Eigenvectors as columns
- `coefficients`: Projection of initial state c_n = <n|psi0>
- `psi0`: Initial state (normalized)
- `n_states`: Number of eigenstates used
- `D`: Hilbert space dimension
"""
struct TimeEvolutionSetup
    energies::Vector{Float64}
    eigenstates::Matrix{ComplexF64}
    coefficients::Vector{ComplexF64}
    psi0::Vector{ComplexF64}
    n_states::Int
    D::Int
end

"""
    prepare_time_evolution(H, psi0; n_states=nothing, use_sparse=true) -> TimeEvolutionSetup

Prepare for time evolution by diagonalizing H and projecting initial state.

This is the EXPENSIVE step - done ONCE before time stepping.

# Arguments
- `H`: Hamiltonian matrix
- `psi0`: Initial state vector
- `n_states`: Number of eigenstates to use (default: all)
- `use_sparse`: Use sparse solver for partial diagonalization

# Returns
TimeEvolutionSetup object for use with evolve_to_time()

# Example
```julia
H = build_H_spin(10, 0.5, terms)
psi0 = build_polarized(10, 0.5, :X, 2)

setup = prepare_time_evolution(H, psi0)  # Expensive, done once
for step in 1:100
    psi_t = evolve_to_time(setup, step * 0.1)  # Cheap, done many times
end
```
"""
function prepare_time_evolution(H::AbstractMatrix, psi0::AbstractVector;
                                 n_states::Union{Int, Nothing}=nothing,
                                 use_sparse::Bool=true)
    D = size(H, 1)
    @assert length(psi0) == D "Initial state dimension mismatch"
    
    # Normalize initial state
    psi0_norm = Vector{ComplexF64}(psi0 / norm(psi0))
    
    # ────────────────────────────────────────────────────────────────
    # Diagonalize Hamiltonian
    # ────────────────────────────────────────────────────────────────
    
    if n_states === nothing || n_states >= D
        # Full diagonalization
        energies, eigenstates_raw = solve_full_spectrum(H)
        n_states_actual = D
    else
        # Partial diagonalization
        energies, eigenstates_raw = solve_spectrum(H, n_states, use_sparse=use_sparse)
        n_states_actual = n_states
    end
    
    # Ensure eigenstates is a proper Matrix{ComplexF64}
    eigenstates = Matrix{ComplexF64}(eigenstates_raw)
    
    # ────────────────────────────────────────────────────────────────
    # Project initial state onto eigenbasis
    # ────────────────────────────────────────────────────────────────
    
    # c_n = <n|psi0>
    coefficients = Vector{ComplexF64}(undef, n_states_actual)
    for n in 1:n_states_actual
        coefficients[n] = dot(eigenstates[:, n], psi0_norm)
    end
    
    # Check completeness
    completeness = sum(abs2.(coefficients))
    if completeness < 0.99
        @warn "Eigenbasis captures only $(round(completeness*100, digits=1))% of initial state. " *
              "Consider using more eigenstates (n_states=$n_states_actual, D=$D)."
    end
    
    return TimeEvolutionSetup(
        energies,
        eigenstates,
        coefficients,
        psi0_norm,
        n_states_actual,
        D
    )
end

# ============================================================================
# PART 4: TIME EVOLUTION - STEPPING
# ============================================================================

"""
    evolve_to_time(setup::TimeEvolutionSetup, t) -> Vector{ComplexF64}

Evolve to time t using precomputed setup.

This is the CHEAP step - just phase factors, O(D * n_states).

# Formula
|psi(t)> = sum_n c_n * exp(-i*E_n*t) |n>

# Arguments
- `setup`: TimeEvolutionSetup from prepare_time_evolution()
- `t`: Time to evolve to

# Returns
State vector psi(t) (normalized)
"""
function evolve_to_time(setup::TimeEvolutionSetup, t::Real)
    psi_t = zeros(ComplexF64, setup.D)
    
    @inbounds for n in 1:setup.n_states
        phase = exp(-im * setup.energies[n] * t)
        c_phase = setup.coefficients[n] * phase
        
        for i in 1:setup.D
            psi_t[i] += c_phase * setup.eigenstates[i, n]
        end
    end
    
    # Normalize (numerical safety)
    return psi_t / norm(psi_t)
end

"""
    evolve_to_time!(psi_t, setup::TimeEvolutionSetup, t)

In-place version of evolve_to_time (avoids allocation).
"""
function evolve_to_time!(psi_t::Vector{ComplexF64}, setup::TimeEvolutionSetup, t::Real)
    fill!(psi_t, zero(ComplexF64))
    
    @inbounds for n in 1:setup.n_states
        phase = exp(-im * setup.energies[n] * t)
        c_phase = setup.coefficients[n] * phase
        
        for i in 1:setup.D
            psi_t[i] += c_phase * setup.eigenstates[i, n]
        end
    end
    
    # Normalize in place
    psi_t ./= norm(psi_t)
    return psi_t
end

# ============================================================================
# PART 5: CONVENIENCE FUNCTIONS FOR TIME EVOLUTION
# ============================================================================

"""
    time_evolve(H, psi0, times; n_states=nothing) -> (times, states)

Convenience function: evolve and return all states at once.
Use prepare_time_evolution() + evolve_to_time() for step-wise control.

# Arguments
- `H`: Hamiltonian matrix
- `psi0`: Initial state
- `times`: Vector of times to evaluate
- `n_states`: Number of eigenstates (default: all)

# Returns
- `times`: Vector of times
- `states`: Vector of state vectors
"""
function time_evolve(H::AbstractMatrix, psi0::AbstractVector, 
                     times::AbstractVector{<:Real};
                     n_states::Union{Int, Nothing}=nothing)
    setup = prepare_time_evolution(H, psi0, n_states=n_states)
    
    states = [evolve_to_time(setup, t) for t in times]
    
    return collect(Float64, times), states
end

"""
    evolve_observable(setup, t, observable) -> Float64

Compute <psi(t)|O|psi(t)> without storing full state.
"""
function evolve_observable(setup::TimeEvolutionSetup, t::Real, 
                           observable::AbstractMatrix)
    psi_t = evolve_to_time(setup, t)
    return real(dot(psi_t, observable * psi_t))
end

# ============================================================================
# PART 6: STATIC TASK SOLVERS (GROUND STATE / SPECTRUM)
# ============================================================================

"""
    solve_ed_static(H, config) -> Dict

Solve static ED tasks (ground_state or spectrum).

# Config for ground_state:
```json
{"algorithm": {"type": "ed_ground_state", "use_sparse": true}}
```

# Config for spectrum:
```json
{"algorithm": {"type": "ed_spectrum", "n_states": 10, "use_sparse": true}}
```
"""
function solve_ed_static(H::AbstractMatrix, config::Dict)
    algo = config["algorithm"]
    task = algo["type"]
    
    if task == "ed_ground_state"
        use_sparse = get(algo, "use_sparse", true)
        E0, state = solve_ground_state(H, use_sparse=use_sparse)
        
        return Dict(
            :task => "ground_state",
            :energy => E0,
            :state => state
        )
        
    elseif task == "ed_spectrum"
        n_states = get(algo, "n_states", 5)
        use_sparse = get(algo, "use_sparse", true)
        energies, states = solve_spectrum(H, n_states, use_sparse=use_sparse)
        gap = n_states >= 2 ? energies[2] - energies[1] : nothing
        
        return Dict(
            :task => "spectrum",
            :energies => energies,
            :states => states,
            :gap => gap
        )
        
    else
        error("Unknown static ED task: $task. Use 'ed_ground_state' or 'ed_spectrum'")
    end
end

# ============================================================================
# PART 7: UTILITY FUNCTIONS
# ============================================================================

"""
    spectral_gap(H; use_sparse=true) -> Float64

Compute spectral gap (E1 - E0).
"""
function spectral_gap(H::AbstractMatrix; use_sparse::Bool=true)
    energies, _ = solve_spectrum(H, 2, use_sparse=use_sparse)
    return energies[2] - energies[1]
end

"""
    energy_variance(H, psi) -> Float64

Compute energy variance <H^2> - <H>^2.
Useful for checking convergence (should be ~0 for eigenstates).
"""
function energy_variance(H::AbstractMatrix, psi::AbstractVector)
    psi_norm = psi / norm(psi)
    E = real(dot(psi_norm, H * psi_norm))
    E2 = real(dot(psi_norm, H * (H * psi_norm)))
    return E2 - E^2
end

"""
    check_eigenstate(H, E, psi; tol=1e-10) -> Bool

Check if psi is an eigenstate of H with eigenvalue E.
"""
function check_eigenstate(H::AbstractMatrix, E::Real, psi::AbstractVector; 
                          tol::Float64=1e-10)
    psi_norm = psi / norm(psi)
    residual = norm(H * psi_norm - E * psi_norm)
    return residual < tol
end

"""
    survival_probability(psi0, psi_t) -> Float64

Compute survival probability |<psi(0)|psi(t)>|^2.
"""
function survival_probability(psi0::AbstractVector, psi_t::AbstractVector)
    return abs2(dot(psi0 / norm(psi0), psi_t / norm(psi_t)))
end

"""
    loschmidt_echo(psi0, psi_t, N) -> Float64

Compute Loschmidt echo -log|<psi(0)|psi(t)>|^2 / N.
"""
function loschmidt_echo(psi0::AbstractVector, psi_t::AbstractVector, N::Int)
    overlap = survival_probability(psi0, psi_t)
    return -log(max(overlap, 1e-300)) / N
end

"""
    get_time_evolution_info(setup::TimeEvolutionSetup) -> Dict

Get information about time evolution setup.
"""
function get_time_evolution_info(setup::TimeEvolutionSetup)
    completeness = sum(abs2.(setup.coefficients))
    
    return Dict(
        :hilbert_dim => setup.D,
        :n_states_used => setup.n_states,
        :completeness => completeness,
        :energy_range => (setup.energies[1], setup.energies[end]),
        :dominant_states => sortperm(abs2.(setup.coefficients), rev=true)[1:min(5, setup.n_states)]
    )
end

"""
    estimate_memory_mb(D; T=ComplexF64) -> Float64

Estimate memory for storing one state vector in MB.
"""
function estimate_memory_mb(D::Int; T::Type=ComplexF64)
    return D * sizeof(T) / (1024^2)
end

"""
    estimate_diagonalization_time(D) -> String

Rough estimate of diagonalization time.
"""
function estimate_diagonalization_time(D::Int)
    # Full diagonalization is O(D^3)
    # Rough benchmark: D=1000 takes ~1 second
    estimated_seconds = (D / 1000)^3
    
    if estimated_seconds < 1
        return "< 1 second"
    elseif estimated_seconds < 60
        return "~$(round(Int, estimated_seconds)) seconds"
    elseif estimated_seconds < 3600
        return "~$(round(estimated_seconds/60, digits=1)) minutes"
    else
        return "~$(round(estimated_seconds/3600, digits=1)) hours"
    end
end