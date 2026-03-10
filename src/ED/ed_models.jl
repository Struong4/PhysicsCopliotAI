# ============================================================================
# ED MODELS - Prebuilt Model Term Generators
# ============================================================================
#
# Generates EDTerm vectors for prebuilt models.
# Equivalent to Builders/modelbuilder.jl in TN.
#
# FLOW:
#   TN:  model config → _get_*_channels() → build_FSM() → build_mpo()
#   ED:  model config → _get_*_terms() → build_H_spin() / build_H_spinboson()
#
# USAGE:
#   # Direct term generation
#   terms = _get_tfi_terms(J, h, :Z, :X)
#   H = build_H_spin(N, S, terms)
#
#   # Config-based (recommended)
#   H = build_H_from_config(config)
#
# ============================================================================

# ============================================================================
# PART 1: SPIN MODEL TERM GENERATORS
# ============================================================================

"""
Transverse Field Ising Model: H = J Σᵢ σᶻᵢσᶻᵢ₊₁ + h Σᵢ σˣᵢ
"""
function _get_tfi_terms(J::Real, h::Real, coupling_dir::Symbol, field_dir::Symbol)
    return EDTerm[
        nearest_neighbor(coupling_dir, coupling_dir, J),
        EDField(field_dir, h)
    ]
end

"""
Heisenberg Model: H = Jx Σᵢ σˣᵢσˣᵢ₊₁ + Jy Σᵢ σʸᵢσʸᵢ₊₁ + Jz Σᵢ σᶻᵢσᶻᵢ₊₁ + hx Σᵢ σˣᵢ + hy Σᵢ σʸᵢ + hz Σᵢ σᶻᵢ
"""
function _get_heisenberg_terms(Jx::Real, Jy::Real, Jz::Real, 
                                hx::Real, hy::Real, hz::Real)
    return EDTerm[
        nearest_neighbor(:X, :X, Jx),
        nearest_neighbor(:Y, :Y, Jy),
        nearest_neighbor(:Z, :Z, Jz),
        EDField(:X, hx),
        EDField(:Y, hy),
        EDField(:Z, hz)
    ]
end

"""
Long-Range Ising Model: H = J Σᵢ<ⱼ σᶻᵢσᶻⱼ/|i-j|^α + h Σᵢ σˣᵢ

Note: EXACT power law, no sum-of-exponentials approximation (unlike TN).
"""
function _get_lri_terms(J::Real, h::Real, alpha::Real, 
                        coupling_dir::Symbol, field_dir::Symbol)
    return EDTerm[
        power_law(coupling_dir, coupling_dir, J, alpha),
        EDField(field_dir, h)
    ]
end

# ============================================================================
# PART 2: SPIN-BOSON MODEL TERM GENERATORS
# ============================================================================

"""
Ising-Dicke Model: H = J Σᵢ σᶻᵢσᶻᵢ₊₁ + h Σᵢ σᶻᵢ + ω b†b + g(b+b†)Σᵢ σˣᵢ
"""
function _get_ising_dicke_terms(J::Real, h::Real, omega::Real, g::Real,
                                 spin_coupling_dir::Symbol, 
                                 spin_field_dir::Symbol,
                                 boson_coupling_dir::Symbol)
    return EDTerm[
        # Spin-spin interaction
        nearest_neighbor(spin_coupling_dir, spin_coupling_dir, J),
        # Spin field
        EDField(spin_field_dir, h),
        # Boson frequency
        EDBosonTerm(:Bn, omega),
        # Spin-boson coupling: g(b + b†)Σᵢ σˣᵢ
        EDSpinBosonCoupling(:a, boson_coupling_dir, g),
        EDSpinBosonCoupling(:adag, boson_coupling_dir, g)
    ]
end

"""
Long-Range Ising-Dicke Model: H = J Σᵢ<ⱼ σᶻᵢσᶻⱼ/|i-j|^α + h Σᵢ σᶻᵢ + ω b†b + g(b+b†)Σᵢ σˣᵢ

Note: EXACT power law for spin-spin interaction.
"""
function _get_lri_dicke_terms(J::Real, h::Real, alpha::Real, 
                               omega::Real, g::Real,
                               spin_coupling_dir::Symbol,
                               spin_field_dir::Symbol,
                               boson_coupling_dir::Symbol)
    return EDTerm[
        # Long-range spin-spin (exact)
        power_law(spin_coupling_dir, spin_coupling_dir, J, alpha),
        # Spin field
        EDField(spin_field_dir, h),
        # Boson frequency
        EDBosonTerm(:Bn, omega),
        # Spin-boson coupling
        EDSpinBosonCoupling(:a, boson_coupling_dir, g),
        EDSpinBosonCoupling(:adag, boson_coupling_dir, g)
    ]
end

# ============================================================================
# PART 3: CUSTOM MODEL PARSERS
# ============================================================================

"""
Parse custom spin terms from config specification.

Input format:
[
    {"type": "EDField", "op": "X", "strength": 0.5},
    {"type": "EDCoupling", "op1": "Z", "op2": "Z", "pattern": "nearest_neighbor", "strength": 1.0},
    {"type": "EDCoupling", "op1": "Z", "op2": "Z", "pattern": "power_law", "strength": 1.0, "alpha": 1.5}
]
"""
function _parse_custom_spin_terms(terms_config::Vector)
    terms = EDTerm[]
    
    for tc in terms_config
        term_type = tc["type"]
        
        if term_type == "EDField"
            push!(terms, EDField(Symbol(tc["op"]), tc["strength"]))
            
        elseif term_type == "EDCoupling"
            op1 = Symbol(tc["op1"])
            op2 = Symbol(tc["op2"])
            pattern = tc["pattern"]
            strength = tc["strength"]
            
            if pattern == "nearest_neighbor"
                push!(terms, nearest_neighbor(op1, op2, strength))
            elseif pattern == "nearest_neighbor_periodic"
                push!(terms, nearest_neighbor_periodic(op1, op2, strength))
            elseif pattern == "power_law"
                alpha = tc["alpha"]
                push!(terms, power_law(op1, op2, strength, alpha))
            elseif pattern == "all_to_all"
                push!(terms, all_to_all(op1, op2, strength))
            elseif pattern == "finite_range"
                range = tc["range"]
                push!(terms, finite_range(op1, op2, strength, range))
            elseif pattern == "finite_range_periodic"
                range = tc["range"]
                push!(terms, finite_range_periodic(op1, op2, strength, range))
            else
                error("Unknown coupling pattern: $pattern")
            end
        else
            error("Unknown term type: $term_type")
        end
    end
    
    return terms
end

"""
Parse custom spin-boson terms from config specification.

Input format:
{
    "spin_terms": [...],           # Same format as custom spin
    "boson_terms": [
        {"op": "Bn", "strength": 1.5}
    ],
    "spinboson_terms": [
        {"boson_op": "a", "spin_op": "X", "strength": 0.5}
    ]
}
"""
function _parse_custom_spinboson_terms(terms_config::Dict)
    terms = EDTerm[]
    
    # Parse spin terms
    if haskey(terms_config, "spin_terms")
        append!(terms, _parse_custom_spin_terms(terms_config["spin_terms"]))
    end
    
    # Parse boson terms
    if haskey(terms_config, "boson_terms")
        for tc in terms_config["boson_terms"]
            push!(terms, EDBosonTerm(Symbol(tc["op"]), tc["strength"]))
        end
    end
    
    # Parse spin-boson coupling terms
    if haskey(terms_config, "spinboson_terms")
        for tc in terms_config["spinboson_terms"]
            push!(terms, EDSpinBosonCoupling(
                Symbol(tc["boson_op"]),
                Symbol(tc["spin_op"]),
                tc["strength"]
            ))
        end
    end
    
    return terms
end

# ============================================================================
# PART 4: MAIN INTERFACE - Build H from Config
# ============================================================================

"""
    build_H_from_config(config) -> SparseMatrixCSC

Unified interface: takes config dict, returns Hamiltonian matrix.
Works for both prebuilt and custom models.

Equivalent to build_mpo_from_config() in TN.
"""
function build_H_from_config(config::Dict)
    system = config["system"]
    model = config["model"]
    model_name = model["name"]
    params = model["params"]
    
    # Parse dtype
    T = _parse_ed_dtype(get(system, "dtype", "ComplexF64"))
    
    # Get system parameters
    system_type = system["type"]
    S = get(system, "S", 0.5)
    
    # ────────────────────────────────────────────────────────────────
    # Spin-only models
    # ────────────────────────────────────────────────────────────────
    if system_type == "spin"
        N = system["N"]
        terms = _get_spin_model_terms(model_name, params)
        return build_H_spin(N, S, terms, T=T)
        
    # ────────────────────────────────────────────────────────────────
    # Spin-boson models
    # ────────────────────────────────────────────────────────────────
    elseif system_type == "spinboson"
        N_spins = system["N_spins"]
        nmax = system["nmax"]
        terms = _get_spinboson_model_terms(model_name, params)
        return build_H_spinboson(N_spins, nmax, S, terms, T=T)
        
    else
        error("Unknown system type: $system_type. Use 'spin' or 'spinboson'")
    end
end

"""
Get terms for spin-only models.
"""
function _get_spin_model_terms(model_name::String, params::Dict)
    if model_name == "transverse_field_ising"
        return _get_tfi_terms(
            params["J"],
            params["h"],
            Symbol(params["coupling_dir"]),
            Symbol(params["field_dir"])
        )
        
    elseif model_name == "heisenberg"
        return _get_heisenberg_terms(
            params["Jx"],
            params["Jy"],
            params["Jz"],
            params["hx"],
            params["hy"],
            params["hz"]
        )
        
    elseif model_name == "long_range_ising"
        return _get_lri_terms(
            params["J"],
            params["h"],
            params["alpha"],
            Symbol(params["coupling_dir"]),
            Symbol(params["field_dir"])
        )
        
    elseif model_name == "custom_spin"
        return _parse_custom_spin_terms(params["terms"])

    else
        # User-registered model: look up from registry
        return _resolve_user_model_ed_terms(model_name, "spin")
    end
end

"""
Get terms for spin-boson models.
"""
function _get_spinboson_model_terms(model_name::String, params::Dict)
    if model_name == "ising_dicke"
        return _get_ising_dicke_terms(
            params["J"],
            params["h"],
            params["omega"],
            params["g"],
            Symbol(params["spin_coupling_dir"]),
            Symbol(params["spin_field_dir"]),
            Symbol(params["boson_coupling_dir"])
        )
        
    elseif model_name == "long_range_ising_dicke"
        return _get_lri_dicke_terms(
            params["J"],
            params["h"],
            params["alpha"],
            params["omega"],
            params["g"],
            Symbol(params["spin_coupling_dir"]),
            Symbol(params["spin_field_dir"]),
            Symbol(params["boson_coupling_dir"])
        )
        
    elseif model_name == "custom_spinboson"
        return _parse_custom_spinboson_terms(params["terms"])

    else
        # User-registered model: look up from registry
        return _resolve_user_model_ed_terms(model_name, "spinboson")
    end
end

"""
    _resolve_user_model_ed_terms(name, expected_system_type)

Look up a user-registered model from the registry and return its ED terms.
"""
function _resolve_user_model_ed_terms(name::String, expected_system_type::String)
    project_root = dirname(dirname(@__DIR__))
    registry_path = joinpath(project_root, "registry", "models.json")

    if !isfile(registry_path)
        error("Registry file not found: $registry_path")
    end

    registry = JSON.parsefile(registry_path)
    user_models = get(get(registry, "user_models", Dict()), "models", Dict())

    if !haskey(user_models, name)
        error("Unknown model: \"$name\"\n" *
              "Not found in prebuilt models or user registry.\n" *
              "Available user models: $(join(keys(user_models), ", "))")
    end

    model_def = user_models[name]
    sys_type = get(model_def, "system_type", "spin")

    if sys_type != expected_system_type
        error("Model '$name' is a $sys_type model but was used in a $expected_system_type system config")
    end

    if haskey(model_def, "terms")
        if sys_type == "spin"
            return _parse_custom_spin_terms(model_def["terms"])
        else
            return _parse_custom_spinboson_terms(model_def["terms"])
        end
    elseif haskey(model_def, "channels")
        # Model was saved as TN but used in ED — need to convert channels to terms
        # For now, error with a clear message
        error("Model '$name' was registered with TN channels but is being used with an ED algorithm.\n" *
              "Re-register it with ED backend, or use a TN algorithm (DMRG/TDVP).")
    else
        error("Model '$name' has no 'terms' or 'channels' definition in registry")
    end
end

"""
Parse dtype string to Julia type.
"""
function _parse_ed_dtype(dtype_str::String)
    if dtype_str == "Float64"
        return Float64
    elseif dtype_str == "ComplexF64"
        return ComplexF64
    else
        error("Unknown dtype: $dtype_str. Use 'Float64' or 'ComplexF64'")
    end
end