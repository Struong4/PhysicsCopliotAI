# ============================================================================
# ED STATES - State Vector Builders
# ============================================================================
#
# Builds state vectors for exact diagonalization.
# Equivalent to Builders/statebuilder.jl in TN.
#
# FLOW:
#   TN:  config → pattern → product_state() → MPS
#   ED:  config → pattern → build_state_vector() → Vector
#
# USAGE:
#   # Direct construction
#   psi = build_polarized(N, S, :Z, 1)
#   psi = build_neel(N, S, :Z)
#   psi = build_random(N, S)
#
#   # Config-based (recommended)
#   psi = build_state_from_config(config)
#
# ============================================================================

using LinearAlgebra
using SparseArrays
using Random

# ============================================================================
# PART 1: SPIN-ONLY PREBUILT STATES
# ============================================================================

"""
    build_polarized(N, S, direction, eigenstate; T=ComplexF64) -> Vector

All spins aligned in same eigenstate of given direction.

# Arguments
- `N::Int`: Number of sites
- `S::Real`: Spin quantum number
- `direction::Symbol`: Quantization axis (:X, :Y, :Z)
- `eigenstate::Int`: Which eigenstate (1 = lowest, d = highest)
- `T::Type`: Element type

# Example
```julia
# All spins in |↑⟩ (highest Sz eigenstate)
psi = build_polarized(10, 0.5, :Z, 2)

# All spins in |↓⟩ (lowest Sz eigenstate)
psi = build_polarized(10, 0.5, :Z, 1)
```
"""
function build_polarized(N::Int, S::Real, direction::Symbol, eigenstate::Int; 
                         T::Type=ComplexF64)
    d = Int(2S + 1)
    @assert 1 <= eigenstate <= d "eigenstate must be in [1, $d]"
    
    # Get eigenvector of spin operator
    ops = spin_matrices(S, T=T)
    op_matrix = Matrix(ops[direction])
    eig = eigen(Hermitian(op_matrix))
    
    # Sort by eigenvalue (ascending)
    idx = sortperm(eig.values)
    local_state = eig.vectors[:, idx[eigenstate]]
    
    # Build product state: |psi⟩ = |s⟩ ⊗ |s⟩ ⊗ ... ⊗ |s⟩
    psi = local_state
    for _ in 2:N
        psi = kron(psi, local_state)
    end
    
    return psi
end

"""
    build_neel(N, S, direction; even_state=1, odd_state=2, T=ComplexF64) -> Vector

Alternating spin configuration (Neel state).

# Arguments
- `N::Int`: Number of sites
- `S::Real`: Spin quantum number
- `direction::Symbol`: Quantization axis
- `even_state::Int`: Eigenstate for even sites (default: 1 = lowest)
- `odd_state::Int`: Eigenstate for odd sites (default: 2 = highest for S=1/2)

# Example
```julia
# |↓↑↓↑↓↑...⟩
psi = build_neel(10, 0.5, :Z)

# |↑↓↑↓↑↓...⟩
psi = build_neel(10, 0.5, :Z, even_state=2, odd_state=1)
```
"""
function build_neel(N::Int, S::Real, direction::Symbol; 
                    even_state::Int=1, odd_state::Int=2, T::Type=ComplexF64)
    d = Int(2S + 1)
    @assert 1 <= even_state <= d "even_state must be in [1, $d]"
    @assert 1 <= odd_state <= d "odd_state must be in [1, $d]"
    
    # Get eigenvectors
    ops = spin_matrices(S, T=T)
    op_matrix = Matrix(ops[direction])
    eig = eigen(Hermitian(op_matrix))
    idx = sortperm(eig.values)
    
    state_even = eig.vectors[:, idx[even_state]]
    state_odd = eig.vectors[:, idx[odd_state]]
    
    # Build alternating product state
    psi = (1 % 2 == 1) ? state_odd : state_even
    for i in 2:N
        local_state = (i % 2 == 1) ? state_odd : state_even
        psi = kron(psi, local_state)
    end
    
    return psi
end

"""
    build_kink(N, S, direction; position, left_state=1, right_state=2, T=ComplexF64) -> Vector

Domain wall state: all sites ≤ position in left_state, rest in right_state.

# Arguments
- `N::Int`: Number of sites
- `S::Real`: Spin quantum number
- `direction::Symbol`: Quantization axis
- `position::Int`: Kink position (sites 1:position have left_state)
- `left_state::Int`: Eigenstate for left region
- `right_state::Int`: Eigenstate for right region

# Example
```julia
# |↓↓↓↓↓↑↑↑↑↑⟩ (kink in middle)
psi = build_kink(10, 0.5, :Z, position=5)
```
"""
function build_kink(N::Int, S::Real, direction::Symbol; 
                    position::Int, left_state::Int=1, right_state::Int=2, 
                    T::Type=ComplexF64)
    d = Int(2S + 1)
    @assert 1 <= position < N "position must be in [1, N-1]"
    @assert 1 <= left_state <= d "left_state must be in [1, $d]"
    @assert 1 <= right_state <= d "right_state must be in [1, $d]"
    
    # Get eigenvectors
    ops = spin_matrices(S, T=T)
    op_matrix = Matrix(ops[direction])
    eig = eigen(Hermitian(op_matrix))
    idx = sortperm(eig.values)
    
    state_left = eig.vectors[:, idx[left_state]]
    state_right = eig.vectors[:, idx[right_state]]
    
    # Build product state with kink
    psi = (1 <= position) ? state_left : state_right
    for i in 2:N
        local_state = (i <= position) ? state_left : state_right
        psi = kron(psi, local_state)
    end
    
    return psi
end

"""
    build_domain(N, S, direction; start_index, domain_size, base_state=1, flip_state=2, T=ComplexF64) -> Vector

Domain state: flipped region within base state.

# Arguments
- `N::Int`: Number of sites
- `S::Real`: Spin quantum number
- `direction::Symbol`: Quantization axis
- `start_index::Int`: Start of flipped domain
- `domain_size::Int`: Size of flipped domain
- `base_state::Int`: Background eigenstate
- `flip_state::Int`: Flipped region eigenstate

# Example
```julia
# |↓↓↓↑↑↑↓↓↓↓⟩ (domain of 3 flips starting at site 4)
psi = build_domain(10, 0.5, :Z, start_index=4, domain_size=3)
```
"""
function build_domain(N::Int, S::Real, direction::Symbol;
                      start_index::Int, domain_size::Int,
                      base_state::Int=1, flip_state::Int=2, T::Type=ComplexF64)
    d = Int(2S + 1)
    @assert 1 <= start_index <= N "start_index must be in [1, N]"
    @assert 1 <= base_state <= d "base_state must be in [1, $d]"
    @assert 1 <= flip_state <= d "flip_state must be in [1, $d]"
    
    end_index = min(start_index + domain_size - 1, N)
    
    # Get eigenvectors
    ops = spin_matrices(S, T=T)
    op_matrix = Matrix(ops[direction])
    eig = eigen(Hermitian(op_matrix))
    idx = sortperm(eig.values)
    
    state_base = eig.vectors[:, idx[base_state]]
    state_flip = eig.vectors[:, idx[flip_state]]
    
    # Build product state with domain
    function get_local_state(i)
        return (start_index <= i <= end_index) ? state_flip : state_base
    end
    
    psi = get_local_state(1)
    for i in 2:N
        psi = kron(psi, get_local_state(i))
    end
    
    return psi
end

"""
    build_random(N, S; T=ComplexF64, seed=nothing) -> Vector

Random normalized state vector.

# Arguments
- `N::Int`: Number of sites
- `S::Real`: Spin quantum number
- `T::Type`: Element type
- `seed`: Random seed (optional)

# Example
```julia
psi = build_random(10, 0.5)
psi = build_random(10, 0.5, seed=42)  # Reproducible
```
"""
function build_random(N::Int, S::Real; T::Type=ComplexF64, seed=nothing)
    if seed !== nothing
        Random.seed!(seed)
    end
    
    d = Int(2S + 1)
    D = d^N
    
    # Random complex vector
    if T <: Complex
        psi = randn(T, D)
    else
        psi = randn(D)
    end
    
    # Normalize
    psi = psi / norm(psi)
    
    return Vector{T}(psi)
end

# ============================================================================
# PART 2: SPIN-BOSON PREBUILT STATES
# ============================================================================

"""
    build_spinboson_polarized(N_spins, nmax, boson_level, S, direction, eigenstate; T=ComplexF64) -> Vector

Boson in Fock state + all spins polarized.

# Arguments
- `N_spins::Int`: Number of spin sites
- `nmax::Int`: Boson Fock space cutoff
- `boson_level::Int`: Boson occupation (0 to nmax)
- `S::Real`: Spin quantum number
- `direction::Symbol`: Spin quantization axis
- `eigenstate::Int`: Spin eigenstate

# Example
```julia
# Vacuum boson + all spins up
psi = build_spinboson_polarized(5, 4, 0, 0.5, :Z, 2)

# 3 photons + all spins down
psi = build_spinboson_polarized(5, 4, 3, 0.5, :Z, 1)
```
"""
function build_spinboson_polarized(N_spins::Int, nmax::Int, boson_level::Int,
                                    S::Real, direction::Symbol, eigenstate::Int;
                                    T::Type=ComplexF64)
    @assert 0 <= boson_level <= nmax "boson_level must be in [0, $nmax]"
    
    d_spin = Int(2S + 1)
    d_boson = nmax + 1
    
    # Boson Fock state |n⟩
    boson_state = zeros(T, d_boson)
    boson_state[boson_level + 1] = one(T)
    
    # Spin polarized state
    spin_state = build_polarized(N_spins, S, direction, eigenstate, T=T)
    
    # |psi⟩ = |boson⟩ ⊗ |spins⟩
    return kron(boson_state, spin_state)
end

"""
    build_spinboson_neel(N_spins, nmax, boson_level, S, direction; even_state=1, odd_state=2, T=ComplexF64) -> Vector

Boson in Fock state + Neel spin configuration.
"""
function build_spinboson_neel(N_spins::Int, nmax::Int, boson_level::Int,
                               S::Real, direction::Symbol;
                               even_state::Int=1, odd_state::Int=2,
                               T::Type=ComplexF64)
    @assert 0 <= boson_level <= nmax "boson_level must be in [0, $nmax]"
    
    d_boson = nmax + 1
    
    # Boson Fock state
    boson_state = zeros(T, d_boson)
    boson_state[boson_level + 1] = one(T)
    
    # Spin Neel state
    spin_state = build_neel(N_spins, S, direction, 
                            even_state=even_state, odd_state=odd_state, T=T)
    
    return kron(boson_state, spin_state)
end

"""
    build_spinboson_kink(N_spins, nmax, boson_level, S, direction; position, left_state=1, right_state=2, T=ComplexF64) -> Vector

Boson in Fock state + spin kink configuration.
"""
function build_spinboson_kink(N_spins::Int, nmax::Int, boson_level::Int,
                               S::Real, direction::Symbol;
                               position::Int, left_state::Int=1, right_state::Int=2,
                               T::Type=ComplexF64)
    @assert 0 <= boson_level <= nmax "boson_level must be in [0, $nmax]"
    
    d_boson = nmax + 1
    
    # Boson Fock state
    boson_state = zeros(T, d_boson)
    boson_state[boson_level + 1] = one(T)
    
    # Spin kink state
    spin_state = build_kink(N_spins, S, direction,
                            position=position, left_state=left_state, 
                            right_state=right_state, T=T)
    
    return kron(boson_state, spin_state)
end

"""
    build_spinboson_domain(N_spins, nmax, boson_level, S, direction; start_index, domain_size, base_state=1, flip_state=2, T=ComplexF64) -> Vector

Boson in Fock state + spin domain configuration.
"""
function build_spinboson_domain(N_spins::Int, nmax::Int, boson_level::Int,
                                 S::Real, direction::Symbol;
                                 start_index::Int, domain_size::Int,
                                 base_state::Int=1, flip_state::Int=2,
                                 T::Type=ComplexF64)
    @assert 0 <= boson_level <= nmax "boson_level must be in [0, $nmax]"
    
    d_boson = nmax + 1
    
    # Boson Fock state
    boson_state = zeros(T, d_boson)
    boson_state[boson_level + 1] = one(T)
    
    # Spin domain state
    spin_state = build_domain(N_spins, S, direction,
                              start_index=start_index, domain_size=domain_size,
                              base_state=base_state, flip_state=flip_state, T=T)
    
    return kron(boson_state, spin_state)
end

"""
    build_spinboson_random(N_spins, nmax, S; T=ComplexF64, seed=nothing) -> Vector

Random normalized state in spin-boson Hilbert space.
"""
function build_spinboson_random(N_spins::Int, nmax::Int, S::Real;
                                 T::Type=ComplexF64, seed=nothing)
    if seed !== nothing
        Random.seed!(seed)
    end
    
    d_spin = Int(2S + 1)
    d_boson = nmax + 1
    D = d_boson * d_spin^N_spins
    
    if T <: Complex
        psi = randn(T, D)
    else
        psi = randn(D)
    end
    
    return Vector{T}(psi / norm(psi))
end

# ============================================================================
# PART 3: CUSTOM STATE BUILDERS
# ============================================================================

"""
    build_custom_product_state(N, S, site_configs; T=ComplexF64) -> Vector

Build product state with custom configuration per site.

# Arguments
- `N::Int`: Number of sites
- `S::Real`: Spin quantum number
- `site_configs::Vector`: Array of (direction, eigenstate) tuples

# Example
```julia
# |↑_z ↓_z ↑_x ↓_y⟩
configs = [(:Z, 2), (:Z, 1), (:X, 2), (:Y, 1)]
psi = build_custom_product_state(4, 0.5, configs)
```
"""
function build_custom_product_state(N::Int, S::Real, site_configs::Vector;
                                     T::Type=ComplexF64)
    @assert length(site_configs) == N "site_configs length must match N"
    
    d = Int(2S + 1)
    ops = spin_matrices(S, T=T)
    
    # Build first site state
    dir, eig_idx = site_configs[1]
    op_matrix = Matrix(ops[dir])
    eig = eigen(Hermitian(op_matrix))
    idx = sortperm(eig.values)
    psi = eig.vectors[:, idx[eig_idx]]
    
    # Tensor product with remaining sites
    for i in 2:N
        dir, eig_idx = site_configs[i]
        op_matrix = Matrix(ops[dir])
        eig = eigen(Hermitian(op_matrix))
        idx = sortperm(eig.values)
        local_state = eig.vectors[:, idx[eig_idx]]
        psi = kron(psi, local_state)
    end
    
    return psi
end

"""
    build_spinboson_custom_state(N_spins, nmax, boson_level, S, site_configs; T=ComplexF64) -> Vector

Build spin-boson state with custom spin configuration per site.

# Arguments
- `N_spins::Int`: Number of spin sites
- `nmax::Int`: Boson cutoff
- `boson_level::Int`: Boson occupation
- `S::Real`: Spin quantum number
- `site_configs::Vector`: Array of (direction, eigenstate) tuples for spins

# Example
```julia
# 2 photons + custom spin pattern |↑_z ↓_z ↑_x⟩
configs = [(:Z, 2), (:Z, 1), (:X, 2)]
psi = build_spinboson_custom_state(3, 4, 2, 0.5, configs)
```
"""
function build_spinboson_custom_state(N_spins::Int, nmax::Int, boson_level::Int,
                                       S::Real, site_configs::Vector;
                                       T::Type=ComplexF64)
    @assert 0 <= boson_level <= nmax "boson_level must be in [0, $nmax]"
    @assert length(site_configs) == N_spins "site_configs length must match N_spins"
    
    d_boson = nmax + 1
    
    # Boson Fock state
    boson_state = zeros(T, d_boson)
    boson_state[boson_level + 1] = one(T)
    
    # Custom spin state
    spin_state = build_custom_product_state(N_spins, S, site_configs, T=T)
    
    return kron(boson_state, spin_state)
end

# ============================================================================
# PART 4: MAIN INTERFACE - Config → State Vector
# ============================================================================

"""
    build_state_from_config(config) -> Vector

Build state vector from configuration dict.
Equivalent to build_mps_from_config() in TN.

# Config structure
```json
{
    "system": {"type": "spin", "N": 10, "S": 0.5},
    "state": {
        "type": "prebuilt",
        "name": "polarized",
        "params": {"spin_direction": "Z", "eigenstate": 2}
    }
}
```
"""
function build_state_from_config(config::Dict)
    system = config["system"]
    state_config = config["state"]
    
    system_type = system["type"]
    state_type = state_config["type"]
    T = _parse_ed_dtype(get(system, "dtype", "ComplexF64"))
    S = get(system, "S", 0.5)
    
    # ────────────────────────────────────────────────────────────────
    # Spin-only states
    # ────────────────────────────────────────────────────────────────
    if system_type == "spin"
        N = system["N"]
        
        if state_type == "random"
            seed = get(get(state_config, "params", Dict()), "seed", nothing)
            return build_random(N, S, T=T, seed=seed)
            
        elseif state_type == "prebuilt"
            return _build_spin_prebuilt_state(N, S, state_config, T)
            
        elseif state_type == "custom"
            return _build_spin_custom_state(N, S, state_config, T)
            
        else
            error("Unknown state type: $state_type. Use 'prebuilt', 'custom', or 'random'")
        end
        
    # ────────────────────────────────────────────────────────────────
    # Spin-boson states
    # ────────────────────────────────────────────────────────────────
    elseif system_type == "spinboson"
        N_spins = system["N_spins"]
        nmax = system["nmax"]
        
        if state_type == "random"
            seed = get(get(state_config, "params", Dict()), "seed", nothing)
            return build_spinboson_random(N_spins, nmax, S, T=T, seed=seed)
            
        elseif state_type == "prebuilt"
            return _build_spinboson_prebuilt_state(N_spins, nmax, S, state_config, T)
            
        elseif state_type == "custom"
            return _build_spinboson_custom_state(N_spins, nmax, S, state_config, T)
            
        else
            error("Unknown state type: $state_type. Use 'prebuilt', 'custom', or 'random'")
        end
        
    else
        error("Unknown system type: $system_type. Use 'spin' or 'spinboson'")
    end
end

# ────────────────────────────────────────────────────────────────────
# Spin prebuilt state dispatcher
# ────────────────────────────────────────────────────────────────────
function _build_spin_prebuilt_state(N::Int, S::Real, state_config::Dict, T::Type)
    name = state_config["name"]
    params = get(state_config, "params", Dict())
    
    direction = Symbol(get(params, "spin_direction", "Z"))
    
    if name == "polarized"
        eigenstate = get(params, "eigenstate", 2)
        return build_polarized(N, S, direction, eigenstate, T=T)
        
    elseif name == "neel"
        even_state = get(params, "even_state", 1)
        odd_state = get(params, "odd_state", 2)
        return build_neel(N, S, direction, even_state=even_state, odd_state=odd_state, T=T)
        
    elseif name == "kink"
        position = params["position"]
        left_state = get(params, "left_state", 1)
        right_state = get(params, "right_state", 2)
        return build_kink(N, S, direction, position=position,
                          left_state=left_state, right_state=right_state, T=T)
        
    elseif name == "domain"
        start_index = params["start_index"]
        domain_size = params["domain_size"]
        base_state = get(params, "base_state", 1)
        flip_state = get(params, "flip_state", 2)
        return build_domain(N, S, direction, start_index=start_index,
                            domain_size=domain_size, base_state=base_state,
                            flip_state=flip_state, T=T)
        
    else
        error("Unknown spin prebuilt state: $name\n" *
              "Available: polarized, neel, kink, domain")
    end
end

# ────────────────────────────────────────────────────────────────────
# Spin custom state dispatcher
# ────────────────────────────────────────────────────────────────────
function _build_spin_custom_state(N::Int, S::Real, state_config::Dict, T::Type)
    site_configs_raw = state_config["site_configs"]
    
    # Parse [[dir, eigenstate], ...] → [(Symbol, Int), ...]
    site_configs = [(Symbol(sc[1]), sc[2]) for sc in site_configs_raw]
    
    return build_custom_product_state(N, S, site_configs, T=T)
end

# ────────────────────────────────────────────────────────────────────
# Spin-boson prebuilt state dispatcher
# ────────────────────────────────────────────────────────────────────
function _build_spinboson_prebuilt_state(N_spins::Int, nmax::Int, S::Real,
                                          state_config::Dict, T::Type)
    name = state_config["name"]
    params = get(state_config, "params", Dict())
    
    boson_level = get(params, "boson_level", 0)
    direction = Symbol(get(params, "spin_direction", "Z"))
    
    if name == "polarized"
        eigenstate = get(params, "spin_eigenstate", 2)
        return build_spinboson_polarized(N_spins, nmax, boson_level, S, direction,
                                          eigenstate, T=T)
        
    elseif name == "neel"
        even_state = get(params, "even_state", 1)
        odd_state = get(params, "odd_state", 2)
        return build_spinboson_neel(N_spins, nmax, boson_level, S, direction,
                                     even_state=even_state, odd_state=odd_state, T=T)
        
    elseif name == "kink"
        position = params["position"]
        left_state = get(params, "left_state", 1)
        right_state = get(params, "right_state", 2)
        return build_spinboson_kink(N_spins, nmax, boson_level, S, direction,
                                     position=position, left_state=left_state,
                                     right_state=right_state, T=T)
        
    elseif name == "domain"
        start_index = params["start_index"]
        domain_size = params["domain_size"]
        base_state = get(params, "base_state", 1)
        flip_state = get(params, "flip_state", 2)
        return build_spinboson_domain(N_spins, nmax, boson_level, S, direction,
                                       start_index=start_index, domain_size=domain_size,
                                       base_state=base_state, flip_state=flip_state, T=T)
        
    else
        error("Unknown spin-boson prebuilt state: $name\n" *
              "Available: polarized, neel, kink, domain")
    end
end

# ────────────────────────────────────────────────────────────────────
# Spin-boson custom state dispatcher
# ────────────────────────────────────────────────────────────────────
function _build_spinboson_custom_state(N_spins::Int, nmax::Int, S::Real,
                                        state_config::Dict, T::Type)
    params = state_config["params"]
    boson_level = get(params, "boson_level", 0)
    site_configs_raw = params["site_configs"]
    
    # Parse [[dir, eigenstate], ...] → [(Symbol, Int), ...]
    site_configs = [(Symbol(sc[1]), sc[2]) for sc in site_configs_raw]
    
    return build_spinboson_custom_state(N_spins, nmax, boson_level, S, site_configs, T=T)
end