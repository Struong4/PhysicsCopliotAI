# ============================================================================
# UNIFIED OBSERVABLE CALCULATION RUNNER
# ============================================================================
#
# Single entry point for calculating observables on ALL simulation types:
# TN (DMRG/TDVP) and ED (ed_spectrum/ed_time_evolution).
#
# The engine automatically detects algorithm type from the saved config.
#
# PRIMARY ENTRY POINT (run_id-based):
#   obs_run_id, obs_run_dir = run_observable_from_run_id(
#       "20260309_143000_abc12345",
#       Dict("type" => "entanglement_entropy", "params" => Dict("bond" => 10)),
#       Dict("selection" => "all")
#   )
#
# LEGACY ENTRY POINT (full config-based):
#   config = JSON.parsefile("analysis_config.json")
#   obs_run_id, obs_run_dir = run_observable_calculation_from_config(config)
#
# The simulation config (system, model, algorithm) is loaded from the saved
# run directory — callers only need to provide run_id + observable + selection.
#
# UNIFIED OBSERVABLE TYPES (work for both TN and ED):
#   "single_site_expectation"    - Local ⟨Oᵢ⟩
#   "subsystem_expectation_sum"  - Sum ⟨Σᵢ Oᵢ⟩ over range [l,m]
#   "two_site_expectation"       - Two-point ⟨OᵢPⱼ⟩ (different operators)
#   "correlation_function"       - Two-point ⟨OᵢOⱼ⟩ (same operator)
#   "connected_correlation"      - Connected ⟨OᵢOⱼ⟩ - ⟨Oᵢ⟩⟨Oⱼ⟩
#   "entanglement_entropy"       - von Neumann / Renyi entropy
#   "entanglement_spectrum"      - Schmidt values
#   "energy_expectation"         - ⟨H⟩
#   "energy_variance"            - ⟨H²⟩ - ⟨H⟩²
#
# ============================================================================

using JSON
using JLD2
using LinearAlgebra
using SparseArrays

# ============================================================================
# PART 1: TN Operator Builder
# ============================================================================

"""
    _build_tn_operator(op_config) → Matrix

Convert operator specification to matrix for TN observables (spin-1/2).
"""
function _build_tn_operator(op_config)
    if op_config isa AbstractArray
        return op_config
    end
    
    if op_config == "Sz" || op_config == "Z"
        return [0.5 0.0; 0.0 -0.5]
    elseif op_config == "Sx" || op_config == "X"
        return [0.0 0.5; 0.5 0.0]
    elseif op_config == "Sy" || op_config == "Y"
        return [0.0 -0.5im; 0.5im 0.0]
    elseif op_config == "Sp" || op_config == "+"
        return [0.0 1.0; 0.0 0.0]
    elseif op_config == "Sm" || op_config == "-"
        return [0.0 0.0; 1.0 0.0]
    else
        error("Unknown TN operator: $op_config. Use 'X/Sx', 'Y/Sy', 'Z/Sz', 'Sp/+', 'Sm/-' or provide matrix")
    end
end

# Alias for backward compatibility
const _build_operator_from_config = _build_tn_operator

# ============================================================================
# PART 2: ED Operator Builder
# ============================================================================

"""
    _build_ed_operator(op_config, S) → Matrix

Build ED operator matrix for given spin S using spin_matrices.
"""
function _build_ed_operator(op_config, S::Real=0.5)
    if op_config isa AbstractArray
        return op_config
    end
    
    # Use ED spin_matrices function
    ops = spin_matrices(S)
    
    # Map common names to symbols
    op_map = Dict(
        "X" => :X, "Sx" => :X,
        "Y" => :Y, "Sy" => :Y,
        "Z" => :Z, "Sz" => :Z,
        "Sp" => :Sp, "+" => :Sp,
        "Sm" => :Sm, "-" => :Sm
    )
    
    if haskey(op_map, op_config)
        return ops[op_map[op_config]]
    elseif haskey(ops, Symbol(op_config))
        return ops[Symbol(op_config)]
    else
        error("Unknown ED operator: $op_config. Use 'X', 'Y', 'Z', 'Sp', 'Sm' or provide matrix")
    end
end

# ============================================================================
# PART 3: Sweep/Step Selection
# ============================================================================

"""
    _get_sweeps_to_process(sweep_config, run_dir) → Vector{Int}

Determine which sweeps/steps to process based on selection config.
Works for both TN sweeps and ED steps.
"""
function _get_sweeps_to_process(sweep_config::Dict, run_dir::String)
    selection = sweep_config["selection"]
    
    metadata_path = joinpath(run_dir, "metadata.json")
    metadata = JSON.parsefile(metadata_path)
    
    # Detect data structure: sweep_data (TN) or step_data (ED)
    if haskey(metadata, "sweep_data")
        data_key = "sweep_data"
        index_key = "sweep"
    elseif haskey(metadata, "step_data")
        data_key = "step_data"
        index_key = "step"
    else
        error("No sweep_data or step_data found in metadata")
    end
    
    available_indices = [entry[index_key] for entry in metadata[data_key]]
    
    if selection == "all"
        return available_indices
        
    elseif selection == "range"
        start_idx, end_idx = sweep_config["range"]
        return filter(s -> start_idx <= s <= end_idx, available_indices)
        
    elseif selection == "specific"
        requested = sweep_config["list"]
        return filter(s -> s in requested, available_indices)
        
    elseif selection == "time_range"
        if !haskey(metadata, "dt")
            error("time_range selection only valid for time evolution runs (TDVP or ed_time_evolution)")
        end
        
        t_start, t_end = sweep_config["time_range"]
        
        available_times = Float64[]
        for entry in metadata[data_key]
            if haskey(entry, "time")
                push!(available_times, entry["time"])
            end
        end
        
        if isempty(available_times)
            error("No time information found in $data_key")
        end
        
        t_min = minimum(available_times)
        t_max = maximum(available_times)
        
        if t_start > t_max
            error("Requested time range [$t_start, $t_end] starts after available data (max t=$t_max)")
        end
        
        if t_end > t_max
            @warn "Requested end time $t_end exceeds available data (max t=$t_max). Using t=$t_max."
            t_end = t_max
        end
        
        selected = Int[]
        for entry in metadata[data_key]
            if haskey(entry, "time")
                t = entry["time"]
                if t_start <= t <= t_end
                    push!(selected, entry[index_key])
                end
            end
        end
        
        return selected
        
    else
        error("Unknown selection: $selection. Use 'all', 'range', 'specific', or 'time_range'")
    end
end

# ============================================================================
# PART 4: TN Observable Dispatcher
# ============================================================================

"""
    _calculate_tn_observable(obs_type, params, mps, ham) → value

Calculate observable for TN (MPS) state.
"""
function _calculate_tn_observable(obs_type::String, params::Dict, 
                                   mps::Vector{<:AbstractArray{T1,3}}, 
                                   ham::Union{Vector{<:AbstractArray{T2,4}},Nothing}=nothing) where {T1,T2}
    
    if obs_type == "single_site_expectation"
        site = params["site"]
        operator = _build_tn_operator(params["operator"])
        return single_site_expectation(site, operator, mps)
        
    elseif obs_type == "subsystem_expectation_sum"
        operator = _build_tn_operator(params["operator"])
        l = params["l"]
        m = params["m"]
        return subsystem_expectation_sum(operator, mps, l, m)
        
    elseif obs_type == "two_site_expectation"
        site_i = params["site_i"]
        site_j = params["site_j"]
        op_i = _build_tn_operator(params["operator_i"])
        op_j = _build_tn_operator(params["operator_j"])
        return two_site_expectation(site_i, op_i, site_j, op_j, mps)
        
    elseif obs_type == "correlation_function"
        site_i = params["site_i"]
        site_j = params["site_j"]
        operator = _build_tn_operator(params["operator"])
        return correlation_function(site_i, site_j, operator, mps)
        
    elseif obs_type == "connected_correlation"
        site_i = params["site_i"]
        site_j = params["site_j"]
        operator = _build_tn_operator(params["operator"])
        return connected_correlation(site_i, site_j, operator, mps)
        
    elseif obs_type == "entanglement_spectrum"
        bond = params["bond"]
        n_values = get(params, "n_values", nothing)
        return entanglement_spectrum(bond, mps; n_values=n_values)
        
    elseif obs_type == "entanglement_entropy"
        bond = params["bond"]
        alpha = get(params, "alpha", 1)
        return entanglement_entropy(bond, mps; alpha=alpha)
        
    elseif obs_type == "energy_expectation"
        if ham === nothing
            error("energy_expectation requires Hamiltonian")
        end
        return energy_expectation(mps, ham)
        
    elseif obs_type == "energy_variance"
        if ham === nothing
            error("energy_variance requires Hamiltonian")
        end
        return energy_variance(mps, ham)
        
    else
        error("Unknown TN observable type: $obs_type\n" *
              "Available: single_site_expectation, subsystem_expectation_sum, two_site_expectation,\n" *
              "  correlation_function, connected_correlation, entanglement_entropy,\n" *
              "  entanglement_spectrum, energy_expectation, energy_variance")
    end
end

# Alias for backward compatibility
const _calculate_observable = _calculate_tn_observable

# ============================================================================
# PART 5: ED Observable Dispatcher (TN-Compatible Names)
# ============================================================================

"""
    _calculate_ed_observable(obs_type, params, psi, system_config; H=nothing) → value

Calculate observable for ED state vector.
Uses same obs_type names as TN for unified config experience.
"""
function _calculate_ed_observable(obs_type::String, params::Dict, 
                                   psi::AbstractVector, system_config::Dict;
                                   H::Union{AbstractMatrix, Nothing}=nothing)
    
    system_type = system_config["type"]
    S = get(system_config, "S", 0.5)
    d = Int(2S + 1)
    
    if system_type == "spin"
        N = system_config["N"]
        nmax = nothing
        d_boson = nothing
    elseif system_type == "spinboson"
        N = system_config["N_spins"]
        nmax = system_config["nmax"]
        d_boson = nmax + 1
    else
        error("Unknown system type: $system_type")
    end
    
    # ════════════════════════════════════════════════════════════════════════
    # LOCAL EXPECTATION VALUES (TN-compatible names)
    # ════════════════════════════════════════════════════════════════════════
    
    if obs_type == "single_site_expectation"
        # TN: single_site_expectation(site, operator, mps)
        # ED: single_site_expectation(site, operator, psi, N, S)
        site = params["site"]
        op = _build_ed_operator(params["operator"], S)
        
        if system_type == "spin"
            return single_site_expectation(site, op, psi, N, S)
        else
            return single_site_expectation_sb(site, op, psi, N, nmax, S)
        end
        
    elseif obs_type == "subsystem_expectation_sum"
        # TN: subsystem_expectation_sum(operator, mps, l, m)
        # ED: subsystem_expectation_sum(operator, psi, l, m, N, S)
        op = _build_ed_operator(params["operator"], S)
        l = params["l"]
        m = params["m"]
        
        if system_type == "spin"
            return subsystem_expectation_sum(op, psi, l, m, N, S)
        else
            return subsystem_expectation_sum_sb(op, psi, l, m, N, nmax, S)
        end
        
    elseif obs_type == "expectation_all_sites"
        # ED-only: returns vector of all local expectations
        op = _build_ed_operator(params["operator"], S)
        
        if system_type == "spin"
            return expectation_value_all_sites(op, psi, N, S)
        else
            return expectation_value_all_sites_sb(op, psi, N, nmax, S)
        end
        
    # ════════════════════════════════════════════════════════════════════════
    # CORRELATION FUNCTIONS (TN-compatible names)
    # ════════════════════════════════════════════════════════════════════════
    
    elseif obs_type == "two_site_expectation"
        # TN: two_site_expectation(site_i, op_i, site_j, op_j, mps)
        # ED: two_site_expectation(site_i, op_i, site_j, op_j, psi, N, S)
        site_i = params["site_i"]
        site_j = params["site_j"]
        op_i = _build_ed_operator(params["operator_i"], S)
        op_j = _build_ed_operator(params["operator_j"], S)
        
        if system_type == "spin"
            return two_site_expectation(site_i, op_i, site_j, op_j, psi, N, S)
        else
            return two_site_expectation_sb(site_i, op_i, site_j, op_j, psi, N, nmax, S)
        end
        
    elseif obs_type == "correlation_function"
        # TN: correlation_function(site_i, site_j, operator, mps)
        # ED: correlation_function(site_i, site_j, operator, psi, N, S)
        site_i = params["site_i"]
        site_j = params["site_j"]
        op = _build_ed_operator(params["operator"], S)
        
        if system_type == "spin"
            return correlation_function(site_i, site_j, op, psi, N, S)
        else
            return correlation_function_sb(site_i, site_j, op, psi, N, nmax, S)
        end
        
    elseif obs_type == "connected_correlation"
        # TN: connected_correlation(site_i, site_j, operator, mps)
        # ED: connected_correlation(site_i, site_j, operator, psi, N, S)
        site_i = params["site_i"]
        site_j = params["site_j"]
        op = _build_ed_operator(params["operator"], S)
        
        if system_type == "spin"
            return connected_correlation(site_i, site_j, op, psi, N, S)
        else
            return connected_correlation_sb(site_i, site_j, op, psi, N, nmax, S)
        end
        
    elseif obs_type == "correlation_matrix"
        # ED-only: full N×N correlation matrix
        op = _build_ed_operator(params["operator"], S)
        
        if system_type == "spin"
            return correlation_matrix(op, psi, N, S)
        else
            return correlation_matrix_sb(op, psi, N, nmax, S)
        end
        
    # ════════════════════════════════════════════════════════════════════════
    # ENTANGLEMENT (TN-compatible names)
    # ════════════════════════════════════════════════════════════════════════
    
    elseif obs_type == "entanglement_entropy"
        # TN: entanglement_entropy(bond, mps; alpha=1)
        # ED: entanglement_entropy(cut, psi, N, d; alpha=1)
        # Accept both "cut" and "bond" for compatibility
        cut = get(params, "cut", get(params, "bond", N ÷ 2))
        alpha = get(params, "alpha", 1)
        
        if system_type == "spin"
            return entanglement_entropy(cut, psi, N, d, alpha=alpha)
        else
            return entanglement_entropy_sb(cut, psi, N, d, d_boson, alpha=alpha)
        end
        
    elseif obs_type == "entanglement_spectrum"
        # TN: entanglement_spectrum(bond, mps; n_values=nothing)
        # ED: entanglement_spectrum(cut, psi, N, d; n_values=nothing)
        cut = get(params, "cut", get(params, "bond", N ÷ 2))
        n_values = get(params, "n_values", nothing)
        
        if system_type == "spin"
            return entanglement_spectrum(cut, psi, N, d, n_values=n_values)
        else
            return entanglement_spectrum_sb(cut, psi, N, d, d_boson, n_values=n_values)
        end
        
    # ════════════════════════════════════════════════════════════════════════
    # ENERGY (TN-compatible names, requires Hamiltonian)
    # ════════════════════════════════════════════════════════════════════════
    
    elseif obs_type == "energy_expectation"
        # TN: energy_expectation(mps, ham)
        # ED: energy_expectation(psi, H)
        if H === nothing
            error("energy_expectation requires Hamiltonian. Rebuild H or pass via extra params.")
        end
        return energy_expectation(psi, H)
        
    elseif obs_type == "energy_variance"
        # TN: energy_variance(mps, ham)
        # ED: energy_variance(psi, H)
        if H === nothing
            error("energy_variance requires Hamiltonian. Rebuild H or pass via extra params.")
        end
        return energy_variance(psi, H)
        
    # ════════════════════════════════════════════════════════════════════════
    # BOSON-SPECIFIC (spin-boson only)
    # ════════════════════════════════════════════════════════════════════════
    
    elseif obs_type == "boson_number"
        if system_type != "spinboson"
            error("boson_number only valid for spinboson systems")
        end
        return boson_number(psi, N, nmax, S)
        
    elseif obs_type == "boson_distribution"
        if system_type != "spinboson"
            error("boson_distribution only valid for spinboson systems")
        end
        return boson_distribution(psi, N, nmax, S)
        
    elseif obs_type == "boson_field"
        if system_type != "spinboson"
            error("boson_field only valid for spinboson systems")
        end
        return boson_field_expectation(psi, N, nmax, S)
        
    elseif obs_type == "boson_spin_entanglement"
        if system_type != "spinboson"
            error("boson_spin_entanglement only valid for spinboson systems")
        end
        alpha = get(params, "alpha", 1)
        return boson_spin_entanglement(psi, N, d, d_boson, alpha=alpha)
        
    # ════════════════════════════════════════════════════════════════════════
    # STATE PROPERTIES & DYNAMICS
    # ════════════════════════════════════════════════════════════════════════
    
    elseif obs_type == "inner_product"
        return inner_product(psi)
        
    elseif obs_type == "fidelity"
        psi_ref = params["psi_ref"]
        return fidelity(psi_ref, psi)
        
    elseif obs_type == "survival_probability"
        psi0 = params["psi0"]
        return survival_probability(psi0, psi)
        
    elseif obs_type == "loschmidt_echo"
        psi0 = params["psi0"]
        return loschmidt_echo(psi0, psi, N)
        
    elseif obs_type == "state_norm"
        return sqrt(inner_product(psi))
        
    # ════════════════════════════════════════════════════════════════════════
    # LEGACY ALIASES (backward compatibility with old config files)
    # ════════════════════════════════════════════════════════════════════════
    
    elseif obs_type == "local_expectation"
        # Old name → redirect to unified name
        return _calculate_ed_observable("single_site_expectation", params, psi, system_config, H=H)
        
    elseif obs_type == "two_point_correlation"
        # Old name → redirect to unified name
        return _calculate_ed_observable("correlation_function", params, psi, system_config, H=H)
        
    elseif obs_type == "bipartite_entanglement_entropy"
        # Old name → redirect to unified name
        return _calculate_ed_observable("entanglement_entropy", params, psi, system_config, H=H)
        
    elseif obs_type == "total_magnetization"
        # Old name → convert to subsystem_expectation_sum over full system
        direction = get(params, "direction", "Z")
        new_params = Dict("operator" => direction, "l" => 1, "m" => N)
        return _calculate_ed_observable("subsystem_expectation_sum", new_params, psi, system_config, H=H)
        
    else
        error("Unknown ED observable type: $obs_type\n" *
              "Available (TN-compatible):\n" *
              "  single_site_expectation, subsystem_expectation_sum, two_site_expectation,\n" *
              "  correlation_function, connected_correlation, entanglement_entropy,\n" *
              "  entanglement_spectrum, energy_expectation, energy_variance\n" *
              "Available (ED-only):\n" *
              "  expectation_all_sites, correlation_matrix, boson_number, boson_distribution,\n" *
              "  boson_field, boson_spin_entanglement, inner_product, fidelity,\n" *
              "  survival_probability, loschmidt_echo, state_norm\n" *
              "Legacy (redirected):\n" *
              "  local_expectation, two_point_correlation, bipartite_entanglement_entropy, total_magnetization")
    end
end

# ============================================================================
# PART 6: Main Observable Runner (UNIFIED)
# ============================================================================

"""
    run_observable_calculation_from_config(config; base_dir="data", obs_base_dir="observables", force_recalculate=false)

Legacy entry point: accepts full config with "simulation" and "analysis" sections.
Locates the simulation run via config hash, then delegates to `run_observable_from_run_id`.

For new code, prefer `run_observable_from_run_id()` which takes a `run_id` directly.
"""
function run_observable_calculation_from_config(config::Dict;
                                               base_dir::String="data",
                                               obs_base_dir::String="observables",
                                               force_recalculate::Bool=false)

    base_dir = abspath(base_dir)
    obs_base_dir = abspath(obs_base_dir)

    sim_config = config["simulation"]
    algorithm = sim_config["algorithm"]["type"]

    # Find simulation run via config hash
    runs = _find_runs_by_config(sim_config, base_dir)

    if isempty(runs)
        error("No simulation found matching config.\n" *
              "Run simulation first with run_simulation_from_config()")
    end

    sim_run = runs[end]
    run_id = sim_run["run_id"]

    # Extract observable and selection configs from the analysis section
    analysis = config["analysis"]
    observable_config = analysis["observable"]

    # Determine selection key based on algorithm
    if is_tn_algorithm(algorithm)
        selection_config = get(analysis, "sweeps", Dict("selection" => "all"))
    elseif algorithm == "ed_time_evolution"
        selection_config = get(analysis, "steps", get(analysis, "sweeps", Dict("selection" => "all")))
    elseif algorithm == "ed_spectrum"
        selection_config = get(analysis, "states", Dict("selection" => "ground"))
    else
        selection_config = get(analysis, "sweeps", Dict("selection" => "all"))
    end

    return run_observable_from_run_id(
        run_id, observable_config, selection_config;
        base_dir=base_dir, obs_base_dir=obs_base_dir,
        force_recalculate=force_recalculate
    )
end

# ============================================================================
# PART 7: TN Observable Handler
# ============================================================================

function _run_tn_observable_calculation(sim_config::Dict, sim_run_dir::String,
                                        obs_run_dir::String, observable_config::Dict,
                                        selection_config::Dict)

    println("\n[4/6] Processing TN observables...")

    # Get sweeps to process
    sweeps_to_process = _get_sweeps_to_process(selection_config, sim_run_dir)
    println("  ✓ Sweeps to process: $(length(sweeps_to_process))")
    println("    Range: $(minimum(sweeps_to_process)) to $(maximum(sweeps_to_process))")

    # Observable config
    obs_type = observable_config["type"]
    obs_params = get(observable_config, "params", Dict())
    println("\n[5/6] Observable type: $obs_type")

    # Build Hamiltonian if needed (requires sim_config to rebuild H)
    needs_ham = obs_type in ["energy_expectation", "energy_variance"]
    ham = nothing
    if needs_ham
        println("  Building Hamiltonian from saved config...")
        ham_mpo = build_mpo_from_config(sim_config)
        ham = ham_mpo.tensors
    end

    # Calculate for each sweep
    println("\n[6/6] Calculating observables...")
    println("="^70)

    for (idx, sweep) in enumerate(sweeps_to_process)
        mps, extra_data = load_mps_sweep(sim_run_dir, sweep)
        obs_value = _calculate_tn_observable(obs_type, obs_params, mps.tensors, ham)
        _save_observable_sweep(obs_value, obs_run_dir, sweep; extra_data=extra_data)

        if idx % max(1, length(sweeps_to_process) ÷ 10) == 0
            println("  Progress: $idx/$(length(sweeps_to_process)) sweeps")
        end
    end

    return length(sweeps_to_process)
end

# ============================================================================
# PART 8: ED Observable Handler
# ============================================================================

function _run_ed_observable_calculation(sim_config::Dict, sim_run_dir::String,
                                        obs_run_dir::String, observable_config::Dict,
                                        selection_config::Dict, algorithm::String)

    println("\n[4/6] Processing ED observables...")

    system_config = sim_config["system"]
    obs_type = observable_config["type"]
    obs_params = get(observable_config, "params", Dict())

    println("  Observable type: $obs_type")

    # Build Hamiltonian if energy observable requested (requires sim_config)
    needs_ham = obs_type in ["energy_expectation", "energy_variance"]
    H = nothing
    if needs_ham
        println("  Building Hamiltonian from saved config...")
        H = build_H_from_config(sim_config)
        println("  ✓ Hamiltonian built: $(size(H, 1)) × $(size(H, 1))")
    end

    if algorithm == "ed_spectrum"
        return _run_ed_spectrum_observable(sim_run_dir, obs_run_dir,
                                           system_config, obs_type, obs_params,
                                           selection_config, H)

    elseif algorithm == "ed_time_evolution"
        return _run_ed_time_evolution_observable(sim_run_dir, obs_run_dir,
                                                  system_config, obs_type, obs_params,
                                                  selection_config, H)
    else
        error("Unknown ED algorithm: $algorithm")
    end
end

# ────────────────────────────────────────────────────────────────────────────
# ED Spectrum Observable
# ────────────────────────────────────────────────────────────────────────────

function _run_ed_spectrum_observable(sim_run_dir, obs_run_dir,
                                     system_config, obs_type, obs_params,
                                     selection_config, H)

    println("\n[5/6] Loading spectrum results...")
    energies, states, _ = load_ed_spectrum(sim_run_dir)
    println("  ✓ Loaded $(length(energies)) eigenstates")

    # Determine which states to analyze
    selection = get(selection_config, "selection", "ground")

    if selection == "ground"
        state_indices = [1]
    elseif selection == "range"
        start_idx, end_idx = selection_config["range"]
        state_indices = collect(start_idx:min(end_idx, length(energies)))
    elseif selection == "specific"
        state_indices = selection_config["list"]
    elseif selection == "all"
        state_indices = collect(1:length(energies))
    else
        state_indices = [1]
    end

    println("  States to analyze: $(length(state_indices))")

    println("\n[6/6] Calculating observables...")
    println("="^70)

    for (idx, state_idx) in enumerate(state_indices)
        psi = states[:, state_idx]
        E = energies[state_idx]

        obs_value = _calculate_ed_observable(obs_type, obs_params, psi, system_config, H=H)

        extra_data = Dict("energy" => E, "state_index" => state_idx)
        _save_observable_sweep(obs_value, obs_run_dir, state_idx; extra_data=extra_data)

        if idx % max(1, length(state_indices) ÷ 10) == 0
            println("  Progress: $idx/$(length(state_indices)) states")
        end
    end

    return length(state_indices)
end

# ────────────────────────────────────────────────────────────────────────────
# ED Time Evolution Observable
# ────────────────────────────────────────────────────────────────────────────

function _run_ed_time_evolution_observable(sim_run_dir, obs_run_dir,
                                           system_config, obs_type, obs_params,
                                           selection_config, H)

    steps_to_process = _get_sweeps_to_process(selection_config, sim_run_dir)
    println("\n[5/6] Steps to process: $(length(steps_to_process))")

    println("\n[6/6] Calculating observables...")
    println("="^70)

    for (idx, step) in enumerate(steps_to_process)
        psi, extra_data = load_ed_step(sim_run_dir, step)
        obs_value = _calculate_ed_observable(obs_type, obs_params, psi, system_config, H=H)
        _save_observable_sweep(obs_value, obs_run_dir, step; extra_data=extra_data)

        if idx % max(1, length(steps_to_process) ÷ 10) == 0
            t = get(extra_data, "time", step)
            println("  Progress: $idx/$(length(steps_to_process)) steps (t = $t)")
        end
    end

    return length(steps_to_process)
end

# ============================================================================
# PART 9: Convenience Functions
# ============================================================================

"""
    _calculate_observable_at_sweep(obs_type, params, sim_run_dir, sweep)

Calculate observable for a single sweep/step (utility function).
"""
function _calculate_observable_at_sweep(obs_type::String, params::Dict, 
                                        sim_run_dir::String, sweep::Int)
    # Load config to detect algorithm
    sim_config = JSON.parsefile(joinpath(sim_run_dir, "config.json"))
    algorithm = sim_config["algorithm"]["type"]
    
    if is_tn_algorithm(algorithm)
        mps, extra_data = load_mps_sweep(sim_run_dir, sweep)
        
        needs_ham = obs_type in ["energy_expectation", "energy_variance"]
        ham = nothing
        if needs_ham
            ham_mpo = build_mpo_from_config(sim_config)
            ham = ham_mpo.tensors
        end
        
        return _calculate_tn_observable(obs_type, params, mps.tensors, ham)
        
    elseif is_ed_algorithm(algorithm)
        # Build H if needed
        needs_ham = obs_type in ["energy_expectation", "energy_variance"]
        H = nothing
        if needs_ham
            H = build_H_from_config(sim_config)
        end
        
        if algorithm == "ed_spectrum"
            energies, states, _ = load_ed_spectrum(sim_run_dir)
            psi = states[:, sweep]
        else
            psi, _ = load_ed_step(sim_run_dir, sweep)
        end
        
        return _calculate_ed_observable(obs_type, params, psi, sim_config["system"], H=H)
    else
        error("Unknown algorithm: $algorithm")
    end
end

"""
    run_observable_from_run_id(run_id, observable_config, selection_config;
                               base_dir="data", obs_base_dir="observables",
                               force_recalculate=false)

Primary entry point for observable calculations. Takes a simulation `run_id`,
loads the simulation config from the saved run directory, and calculates
the requested observable.

The simulation config (needed for rebuilding H, system params, etc.) is loaded
directly from `run_dir/config.json` — no need to pass it in from outside.

# Arguments
- `run_id::String`: Simulation run ID (from catalog query)
- `observable_config::Dict`: Observable specification, e.g.
    `Dict("type" => "correlation_function", "params" => Dict("site_i" => 1, "site_j" => 10, "operator" => "Z"))`
- `selection_config::Dict`: Sweep/step/state selection, e.g.
    `Dict("selection" => "all")` or `Dict("selection" => "range", "range" => [1, 10])`
- `base_dir::String`: Simulation data directory
- `obs_base_dir::String`: Observable output directory
- `force_recalculate::Bool`: Recalculate even if results exist

# Returns
- `(obs_run_id, obs_run_dir)`: Observable run identifier and path
"""
function run_observable_from_run_id(run_id::String,
                                    observable_config::Dict,
                                    selection_config::Dict;
                                    base_dir::String="data",
                                    obs_base_dir::String="observables",
                                    force_recalculate::Bool=false)

    base_dir = abspath(base_dir)
    obs_base_dir = abspath(obs_base_dir)

    println("\n" * "="^70)
    println("Starting Observable Calculation")
    println("="^70)

    # ═══════════════════════════════════════════════════════════════════════════
    # Step 1: Locate simulation run and load saved config
    # ═══════════════════════════════════════════════════════════════════════════

    println("\n[1/6] Locating simulation run: $run_id")

    sim_results = query_catalog(; base_dir=base_dir, run_id=run_id)

    if isempty(sim_results)
        error("Simulation run not found: $run_id\n" *
              "Use query_catalog() or GET /api/query/simulations to find available runs.")
    end

    sim_run_dir = sim_results[1]["run_dir"]
    println("  ✓ Run directory: $sim_run_dir")

    # Load simulation config from saved data (the run directory has everything)
    config_path = joinpath(sim_run_dir, "config.json")
    if !isfile(config_path)
        error("Simulation config not found at: $config_path")
    end
    sim_config = JSON.parsefile(config_path)

    algorithm = sim_config["algorithm"]["type"]
    if is_tn_algorithm(algorithm)
        println("  ✓ Algorithm: $algorithm (TN)")
    elseif is_ed_algorithm(algorithm)
        println("  ✓ Algorithm: $algorithm (ED)")
    else
        error("Unknown algorithm type: $algorithm")
    end

    # ═══════════════════════════════════════════════════════════════════════════
    # Step 2: Assemble full config for hashing/dedup/catalog (internal only)
    # ═══════════════════════════════════════════════════════════════════════════

    # Determine the selection key for this algorithm type
    if is_tn_algorithm(algorithm)
        selection_key = "sweeps"
    elseif algorithm == "ed_time_evolution"
        selection_key = "steps"
    elseif algorithm == "ed_spectrum"
        selection_key = "states"
    else
        selection_key = "sweeps"
    end

    # The full config is assembled internally for deduplication hashing,
    # directory setup, and catalog entry — NOT passed in from outside.
    full_config = Dict(
        "simulation" => sim_config,
        "analysis" => Dict(
            selection_key => selection_config,
            "observable" => observable_config
        )
    )

    # ═══════════════════════════════════════════════════════════════════════════
    # Step 3: Check for existing calculation (deduplication)
    # ═══════════════════════════════════════════════════════════════════════════

    println("\n[2/6] Checking for existing calculations...")

    if !force_recalculate
        existing = _get_completed_observable_run(full_config, run_id, obs_base_dir=obs_base_dir)

        if existing !== nothing
            println("  ✓ Found existing completed calculation!")
            println("  Observable run: $(existing["obs_run_id"])")
            println("  Directory: $(existing["obs_run_dir"])")
            println("\n  Use force_recalculate=true to recompute.")
            return existing["obs_run_id"], existing["obs_run_dir"]
        end
    end

    println("  No completed calculation found. Proceeding...")

    # ═══════════════════════════════════════════════════════════════════════════
    # Step 4: Setup observable directory
    # ═══════════════════════════════════════════════════════════════════════════

    println("\n[3/6] Setting up observable directory...")

    obs_run_id, obs_run_dir = _setup_observable_directory(
        full_config, run_id, algorithm, obs_base_dir=obs_base_dir
    )

    println("  ✓ Observable run ID: $obs_run_id")
    println("  ✓ Observable directory: $obs_run_dir")

    obs_type = observable_config["type"]

    # ═══════════════════════════════════════════════════════════════════════════
    # Step 5-6: Dispatch to TN or ED handler
    # ═══════════════════════════════════════════════════════════════════════════

    try
        local n_processed

        if is_tn_algorithm(algorithm)
            n_processed = _run_tn_observable_calculation(
                sim_config, sim_run_dir, obs_run_dir,
                observable_config, selection_config
            )
        else
            n_processed = _run_ed_observable_calculation(
                sim_config, sim_run_dir, obs_run_dir,
                observable_config, selection_config, algorithm
            )
        end

        # Finalize
        println("="^70)
        println("\nFinalizing...")
        _finalize_observable_run(obs_run_dir, status="completed")

        # Append to observable catalog
        _append_to_observables_catalog(full_config, obs_run_id, run_id, "completed",
                                        obs_run_dir; obs_base_dir=obs_base_dir)

        # Summary
        println("\n" * "="^70)
        println("Observable Calculation Complete")
        println("="^70)
        println("  Simulation run: $run_id")
        println("  Observable run: $obs_run_id")
        println("  Observable type: $obs_type")
        println("  Items processed: $n_processed")
        println("  Results saved in: $obs_run_dir")
        println("="^70)

    catch e
        println("\n❌ Observable calculation failed!")
        _finalize_observable_run(obs_run_dir, status="failed")
        rethrow(e)
    end

    return obs_run_id, obs_run_dir
end

"""
    load_observable_timeseries(obs_run_dir) → Dict

Load all observable results as a time series.

# Returns
Dict with:
- "indices": Vector of sweep/step/state indices
- "values": Vector of observable values
- "times": Vector of times (if available)
- "energies": Vector of energies (if available, for spectrum)
"""
function load_observable_timeseries(obs_run_dir::String)
    metadata_path = joinpath(obs_run_dir, "metadata.json")
    metadata = JSON.parsefile(metadata_path)
    
    indices = Int[]
    values = []
    times = Float64[]
    energies = Float64[]
    
    for sweep_info in metadata["sweep_data"]
        sweep = sweep_info["sweep"]
        obs_value, extra_data = load_observable_sweep(obs_run_dir, sweep)
        
        push!(indices, sweep)
        push!(values, obs_value)
        
        if haskey(extra_data, "time")
            push!(times, extra_data["time"])
        end
        if haskey(extra_data, "energy")
            push!(energies, extra_data["energy"])
        end
    end
    
    result = Dict{String, Any}(
        "indices" => indices,
        "values" => values
    )
    
    if !isempty(times)
        result["times"] = times
    end
    if !isempty(energies)
        result["energies"] = energies
    end
    
    return result
end