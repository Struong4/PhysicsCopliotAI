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
        error("Unknown model name: $name\n" *
              "Available models:\n" *
              "  Pre-built: transverse_field_ising, heisenberg, long_range_ising, spin_boson\n" *
              "  Custom: custom_spin, custom_spinboson")
    end
    
    return channels, system
end
