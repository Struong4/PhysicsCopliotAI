# Builders/mpobuilder_config.jl
# Channel-based MPO builder - unified interface

# ============================================================================
# PART 1: Channel Template Functions (Pre-built Models)
# ============================================================================

"""
Transverse Field Ising Model: H = J Σᵢ σᶻᵢσᶻᵢ₊₁ + h Σᵢ σˣᵢ
"""
function _get_tfim_channels(N, J, h, coupling_dir, field_dir)
    return [
        FiniteRangeCoupling(coupling_dir, coupling_dir, 1, J),
        Field(field_dir, h)
    ]
end

"""
Heisenberg Chain: H = Jx Σᵢ σˣᵢσˣᵢ₊₁ + Jy Σᵢ σʸᵢσʸᵢ₊₁ + Jz Σᵢ σᶻᵢσᶻᵢ₊₁ + hx Σᵢ σˣᵢ + hy Σᵢ σʸᵢ + hz Σᵢ σᶻᵢ
"""
function _get_heisenberg_channels(N, Jx, Jy, Jz, hx, hy, hz)
    return [
        FiniteRangeCoupling(:X, :X, 1, Jx),
        FiniteRangeCoupling(:Y, :Y, 1, Jy),
        FiniteRangeCoupling(:Z, :Z, 1, Jz),
        Field(:X, hx), Field(:Y, hy), Field(:Z, hz)

    ]
end

"""
Long-Range Ising: H = J Σᵢ<ⱼ σᶻᵢσᶻⱼ/|i-j|^α + h Σᵢ σˣᵢ
"""
function _get_longrange_ising_channels(N, J, alpha, n_exp, h, coupling_dir, field_dir)
    return [
        PowerLawCoupling(coupling_dir, coupling_dir, J, alpha, n_exp, N),
        Field(field_dir, h)
    ]
end

"""
Spin-Boson Model: H = ω b†b + J Σᵢ σᶻᵢσᶻᵢ₊₁ + h Σᵢ σᶻᵢ + g(b+b†)Σᵢ σˣᵢ
"""
function _get_spinboson_ising_dikie_channels(N_spins, J, h, omega, g,
                                spin_coupling_dir, spin_field_dir, boson_coupling_dir)
    # Spin-spin interactions
    spinchannel1 = [
        FiniteRangeCoupling(spin_coupling_dir, spin_coupling_dir, 1, J)
        Field(spin_field_dir, h)
    ]
    
    # Boson-spin coupling
    spinchannel2 = [Field(boson_coupling_dir, 1.0)]
    
    return [
        SpinBosonInteraction(spinchannel1, :Ib, 1.0),
        SpinBosonInteraction(spinchannel2, :a, g),
        SpinBosonInteraction(spinchannel2, :adag, g),
        BosonOnly(:Bn, omega)
    ]
end

"""
Spin-Boson Model long-range: H = ω b†b + J Σᵢ<ⱼ σᶻᵢσᶻⱼ/|i-j|^α + h Σᵢ σᶻᵢ + g(b+b†)Σᵢ σˣᵢ
"""
function _get_spinboson_longrange_ising_dikie_channels(N_spins, J, alpha, n_exp, h, omega, g,
                                spin_coupling_dir, spin_field_dir, boson_coupling_dir)
    # Spin-spin interactions
    spinchannel1 = [
        PowerLawCoupling(spin_coupling_dir, spin_coupling_dir, J, alpha, n_exp, N_spins),
        Field(spin_field_dir, h)
    ]
    
    # Boson-spin coupling
    spinchannel2 = [Field(boson_coupling_dir, 1.0)]
    
    return [
        SpinBosonInteraction(spinchannel1, :Ib, 1.0),
        SpinBosonInteraction(spinchannel2, :a, g),
        SpinBosonInteraction(spinchannel2, :adag, g),
        BosonOnly(:Bn, omega)
    ]
end



# ============================================================================
# PART 2: Channel Parsers (Custom Models)
# ============================================================================

"""
Parse spin-only channels from config
"""
function _parse_spin_channels(channels_config)
    channels = Spin[]
    
    for ch in channels_config
        if ch["type"] == "FiniteRangeCoupling"
            push!(channels, FiniteRangeCoupling(
                Symbol(ch["op1"]),
                Symbol(ch["op2"]),
                ch["range"],
                ch["strength"]
            ))

        elseif ch["type"] == "ExpChannelCoupling"
            push!(channels,ExpChannelCoupling(
                Symbol(ch["op1"]),
                Symbol(ch["op2"]),
                ch["amplitude"],
                ch["decay"]
            ))
            
        elseif ch["type"] == "PowerLawCoupling"
            push!(channels, PowerLawCoupling(
                Symbol(ch["op1"]),
                Symbol(ch["op2"]),
                ch["strength"],
                ch["alpha"],
                ch["n_exp"],
                ch["N"]
            ))
            
        elseif ch["type"] == "Field"
            push!(channels, Field(
                Symbol(ch["op"]),
                ch["strength"]
            ))
            
        else
            error("Unknown spin channel type: $(ch["type"])")
        end
    end
    
    return channels
end

"""
Parse spin-boson channels from config
"""
function _parse_spinboson_channels(channels_config)
    channels = Boson[]
    
    # 1. Spin channels → auto-wrap with Ib
    if haskey(channels_config, "spin_channels")
        for ch in _parse_spin_channels(channels_config["spin_channels"])
            push!(channels, SpinBosonInteraction([ch], :Ib, 1.0))
        end
    end
    
    # 2. Boson channels
    if haskey(channels_config, "boson_channels")
        for ch in channels_config["boson_channels"]
            push!(channels, BosonOnly(Symbol(ch["op"]), ch["strength"]))
        end
    end
    
    # 3. Spinboson coupling channels
    if haskey(channels_config, "spinboson_channels")
        for ch in channels_config["spinboson_channels"]
            spin_subchannels = _parse_spin_channels(ch["spin_channels"])
            push!(channels, SpinBosonInteraction(
                spin_subchannels,
                Symbol(ch["boson_op"]),
                ch["strength"]
            ))
        end
    end
    
    return channels
end

# ============================================================================
# PART 3: Helper Functions
# ============================================================================

function _parse_dtype(dtype_str)
    if dtype_str == "Float64"
        return Float64
    elseif dtype_str == "ComplexF64"
        return ComplexF64
    else
        error("Unknown dtype: $dtype_str. Use 'Float64' or 'ComplexF64'")
    end
end

# ============================================================================
# PART 4: Main Interface - Build MPO from Config
# ============================================================================

"""
    build_mpo_from_config(config)

Unified interface: takes config, returns MPO.
Works for both pre-built and custom models.
"""
function build_mpo_from_config(config)
    # Get channels and system parameters
    channels, system_params = _get_channels_from_config(config)
    
    # Build FSM (unified for all models)
    fsm = build_FSM(channels)
    
    # Build MPO (dispatch based on system type)
    if system_params.type == "spin"
        return build_mpo(fsm, N=system_params.N, d=2, T=system_params.dtype)
    else  # spinboson
        return build_mpo(fsm, N=system_params.N, d=2, 
                        nmax=system_params.nmax, T=system_params.dtype)
    end
end

"""
    get_channels_from_config(config)

Extract channels from config (either from pre-built template or custom specification).
Returns (channels, system_params).
"""
function _get_channels_from_config(config)
    name = config["model"]["name"]
    params = config["model"]["params"]
    
    # Parse dtype (common to all)
    dtype = if haskey(params, "dtype")
        _parse_dtype(params["dtype"])
    else
        ComplexF64
    end
    
    # ────────────────────────────────────────────────────────────────────────
    # Pre-built Models: Generate channels from templates
    # ────────────────────────────────────────────────────────────────────────
    
    if name == "transverse_field_ising"
        channels = _get_tfim_channels(
            params["N"],
            params["J"],
            params["h"],
            Symbol(params["coupling_dir"]),
            Symbol(params["field_dir"])
        )
        system = (type="spin", N=params["N"], dtype=dtype)
        
    elseif name == "heisenberg"
        channels = _get_heisenberg_channels(
            params["N"],
            params["Jx"],
            params["Jy"],
            params["Jz"],
            params["hx"],
            params["hy"],
            params["hz"],
        )
        system = (type="spin", N=params["N"], dtype=dtype)
        
    elseif name == "long_range_ising"
        channels = _get_longrange_ising_channels(
            params["N"],
            params["J"],
            params["alpha"],
            params["n_exp"],
            params["h"],
            Symbol(params["coupling_dir"]),
            Symbol(params["field_dir"])
        )
        system = (type="spin", N=params["N"], dtype=dtype)
        
    elseif name == "ising_dicke"
        channels = _get_spinboson_ising_dikie_channels(
            params["N_spins"],
            params["J"],
            params["h"],
            params["omega"],
            params["g"],
            Symbol(params["spin_coupling_dir"]),
            Symbol(params["spin_field_dir"]),
            Symbol(params["boson_coupling_dir"])
        )
        system = (type="spinboson", N=params["N_spins"]+1, 
                 nmax=params["nmax"], dtype=dtype)
                 
    elseif name == "long_range_ising_dicke"
        channels = _get_spinboson_longrange_ising_dikie_channels(
            params["N_spins"],
            params["J"],
            params["alpha"],
            params["n_exp"],
            params["h"],
            params["omega"],
            params["g"],
            Symbol(params["spin_coupling_dir"]),
            Symbol(params["spin_field_dir"]),
            Symbol(params["boson_coupling_dir"])
        )
        system = (type="spinboson", N=params["N_spins"]+1, 
                    nmax=params["nmax"], dtype=dtype)
    
    # ────────────────────────────────────────────────────────────────────────
    # Custom Models: Parse channels from config
    # ────────────────────────────────────────────────────────────────────────
    
    elseif name == "custom_spin"
        channels = _parse_spin_channels(params["channels"])
        system = (type="spin", N=params["N"], dtype=dtype)
        
    elseif name == "custom_spinboson"
        channels = _parse_spinboson_channels(params["channels"])
        system = (type="spinboson", N=params["N_spins"]+1, 
                 nmax=params["nmax"], dtype=dtype)
        
    else
        # User-registered model: look up definition from registry
        channels, system = _resolve_user_model(name, params, dtype)
    end
    
    return channels, system
end

# ============================================================================
# PART 5: User Model Resolution from Registry
# ============================================================================

"""
    _resolve_user_model(name, params, dtype)

Look up a user-registered model from the registry and build its channels.
The registry file (registry/models.json) stores the model definition
(channels for TN, terms for ED) under user_models.models.<name>.
"""
function _resolve_user_model(name::AbstractString, params::Dict, dtype)
    # Find registry/models.json relative to project root
    # Project root is the parent of src/
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
    backend = get(model_def, "backend", "tn")

    if sys_type == "spin"
        if backend == "tn"
            channels = _parse_spin_channels(model_def["channels"])
        else
            channels = _parse_spin_channels_from_ed_terms(model_def["terms"])
        end
        N = get(params, "N", nothing)
        N === nothing && error("User model '$name' requires N in params")
        system = (type="spin", N=N, dtype=dtype)
    else
        # spinboson
        if backend == "tn"
            channels = _parse_spinboson_channels(model_def["channels"])
        else
            channels = _parse_spinboson_channels_from_ed_terms(model_def["terms"])
        end
        N_spins = get(params, "N_spins", nothing)
        nmax = get(params, "nmax", nothing)
        (N_spins === nothing || nmax === nothing) && error("User model '$name' requires N_spins and nmax in params")
        system = (type="spinboson", N=N_spins+1, nmax=nmax, dtype=dtype)
    end

    return channels, system
end

"""
Parse ED terms format back to spin channels.
ED terms have: {type, op/op1/op2, strength, ...}
"""
function _parse_spin_channels_from_ed_terms(terms::Vector)
    channels = []
    for term in terms
        t = term["type"]
        if t == "Field"
            push!(channels, Field(Symbol(term["op"]), term["strength"]))
        elseif t == "Coupling"
            push!(channels, FiniteRangeCoupling(
                Symbol(term["op1"]), Symbol(term["op2"]),
                get(term, "range", 1), term["strength"]
            ))
        elseif t == "ExponentialCoupling"
            push!(channels, ExponentialCoupling(
                Symbol(term["op1"]), Symbol(term["op2"]),
                term["strength"], term["lambda"]
            ))
        end
    end
    return channels
end

"""
Parse ED spinboson terms format back to boson channels.
"""
function _parse_spinboson_channels_from_ed_terms(terms::Dict)
    channels = Boson[]

    # Spin terms → wrap with Ib
    if haskey(terms, "spin_terms")
        for ch in _parse_spin_channels_from_ed_terms(terms["spin_terms"])
            push!(channels, SpinBosonInteraction([ch], :Ib, 1.0))
        end
    end

    # Boson terms
    if haskey(terms, "boson_terms")
        for bt in terms["boson_terms"]
            push!(channels, BosonOnly(Symbol(bt["op"]), bt["strength"]))
        end
    end

    # Spinboson coupling terms
    if haskey(terms, "spinboson_terms")
        for st in terms["spinboson_terms"]
            spin_ch = Field(Symbol(st["spin_op"]), 1.0)
            push!(channels, SpinBosonInteraction(
                [spin_ch], Symbol(st["boson_op"]), st["strength"]
            ))
        end
    end

    return channels
end
