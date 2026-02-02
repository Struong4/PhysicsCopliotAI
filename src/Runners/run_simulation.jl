# ============================================================================
# UNIFIED SIMULATION RUNNER
# ============================================================================
#
# Single entry point for ALL simulations: TN (DMRG/TDVP) and ED.
# The engine automatically detects algorithm type from config and dispatches.
#
# USAGE:
#   config = JSON.parsefile("config.json")
#   result, run_id, run_dir = run_simulation_from_config(config)
#
# SUPPORTED ALGORITHMS:
#   TN:  "dmrg", "tdvp"
#   ED:  "ed_spectrum", "ed_time_evolution"
#
# ============================================================================

# ============================================================================
# PART 1: TN Solver Builders
# ============================================================================

function build_solver_from_config(config)
    solver_config = config["algorithm"]["solver"]
    solver_type = solver_config["type"]
    
    if solver_type == "lanczos"
        krylov_dim = solver_config["krylov_dim"]
        max_iter = solver_config["max_iter"]
        return LanczosSolver(krylov_dim, max_iter)
        
    elseif solver_type == "krylov_exponential"
        krylov_dim = solver_config["krylov_dim"]
        tol = get(solver_config, "tol", 1e-8)
        evol_type = solver_config["evol_type"]
        return KrylovExponential(krylov_dim, tol, evol_type)
        
    else
        error("Unknown solver type: $solver_type. Use 'lanczos' or 'krylov_exponential'")
    end
end

# ============================================================================
# PART 2: TN Options Builders
# ============================================================================

function build_options_from_config(config)
    algorithm_type = config["algorithm"]["type"]
    options_config = config["algorithm"]["options"]

    if algorithm_type == "dmrg"
        chi_max = options_config["chi_max"]
        cutoff = options_config["cutoff"]
        local_dim = options_config["local_dim"]
        return DMRGOptions(chi_max, cutoff, local_dim)
        
    elseif algorithm_type == "tdvp"
        dt = options_config["dt"]
        chi_max = options_config["chi_max"]
        cutoff = options_config["cutoff"]
        local_dim = options_config["local_dim"]
        return TDVPOptions(dt, chi_max, cutoff, local_dim)
        
    else
        error("Unknown TN algorithm type: $algorithm_type. Use 'dmrg' or 'tdvp'")
    end
end

# ============================================================================
# PART 3: Main Simulation Runner (UNIFIED)
# ============================================================================

"""
    run_simulation_from_config(config; base_dir="data", force_rerun=false)

Unified entry point for all simulations. Automatically detects algorithm type
from config and dispatches to appropriate handler.

# Supported Algorithms
- TN: "dmrg", "tdvp"
- ED: "ed_spectrum", "ed_time_evolution"

# Arguments
- `config::Dict`: Full simulation configuration
- `base_dir::String`: Root data directory (default: "data")
- `force_rerun::Bool`: If true, skip deduplication check

# Returns
- `result`: Simulation result (algorithm-dependent)
- `run_id::String`: Unique run identifier
- `run_dir::String`: Path to run directory

# Example
```julia
# Works for any algorithm type
config = JSON.parsefile("configs/my_simulation.json")
result, run_id, run_dir = run_simulation_from_config(config)
```
"""
function run_simulation_from_config(config; base_dir="data", force_rerun=false)
    
    algorithm = config["algorithm"]["type"]
    
    # ════════════════════════════════════════════════════════════════════════
    # Dispatch based on algorithm type
    # ════════════════════════════════════════════════════════════════════════
    
    if is_tn_algorithm(algorithm)
        return _run_tn_simulation(config, base_dir=base_dir, force_rerun=force_rerun)
        
    elseif is_ed_algorithm(algorithm)
        return _run_ed_simulation(config, base_dir=base_dir, force_rerun=force_rerun)
        
    else
        error("Unknown algorithm type: $algorithm\n" *
              "Supported: dmrg, tdvp, ed_spectrum, ed_time_evolution")
    end
end

# ============================================================================
# PART 4: TN Simulation Handler
# ============================================================================

function _run_tn_simulation(config; base_dir="data", force_rerun=false)
    println("="^70)
    println("Starting TN Simulation: $(uppercase(config["algorithm"]["type"]))")
    println("="^70)

    # ════════════════════════════════════════════════════════════════════════
    # DEDUPLICATION CHECK
    # ════════════════════════════════════════════════════════════════════════
    
    println("\n[1/6] Checking for existing runs...")
    
    if !force_rerun
        existing = _get_completed_run(config, base_dir=base_dir)
        
        if existing !== nothing
            println("="^70)
            println("✓ SIMULATION ALREADY COMPLETED")
            println("="^70)
            println("  Run ID: $(existing["run_id"])")
            println("  Path:   $(existing["run_dir"])")
            println("")
            println("  To force re-run, use: force_rerun=true")
            println("="^70)
            
            return nothing, existing["run_id"], existing["run_dir"]
        end
        
        println("  No completed run found. Proceeding with simulation...")
    else
        println("  force_rerun=true. Skipping deduplication check...")
    end
    
    # ════════════════════════════════════════════════════════════════════════
    # DATABASE SETUP
    # ════════════════════════════════════════════════════════════════════════
    
    println("\n[2/6] Setting up database...")
    
    run_id, run_dir = _setup_run_directory(config, base_dir=base_dir)
    println("  ✓ Run ID: $run_id")
    println("  ✓ Data directory: $run_dir")
    
    # ────────────────────────────────────────────────────────────────────────
    # Build System Components
    # ────────────────────────────────────────────────────────────────────────
    
    println("\n[3/6] Building system components...")
        
    # Build Hamiltonian (MPO)
    ham = build_mpo_from_config(config)
    println("  ✓ Hamiltonian: $(length(ham.tensors)) site MPO")
    
    # Build initial state (MPS)
    psi = build_mps_from_config(config)
    println("  ✓ Initial state: $(length(psi.tensors)) site MPS")
    
    # Create MPSState
    state = MPSState(psi, ham; center=1)
    println("  ✓ MPSState created")
    
    # ────────────────────────────────────────────────────────────────────────
    # Parse Algorithm Configuration
    # ────────────────────────────────────────────────────────────────────────
    
    println("\n[4/6] Parsing algorithm configuration...")
        
    # Build solver
    solver = build_solver_from_config(config)
    println("  ✓ Solver: $(typeof(solver))")
    
    # Build options
    options = build_options_from_config(config)
    println("  ✓ Options: $(typeof(options))")
    
    # Get run parameters
    n_sweeps = config["algorithm"]["run"]["n_sweeps"]
    println("  Sweeps: $n_sweeps")
    
    # ────────────────────────────────────────────────────────────────────────
    # Run Simulation
    # ────────────────────────────────────────────────────────────────────────
    
    println("\n[5/6] Running simulation...")
    println("="^70)
    
    try
        if config["algorithm"]["type"] == "dmrg"
            _run_dmrg_simulation(state, solver, options, n_sweeps, run_dir)
            
        elseif config["algorithm"]["type"] == "tdvp"
            _run_tdvp_simulation(state, solver, options, n_sweeps, run_dir)
        end
        
        # ────────────────────────────────────────────────────────────────────
        # Finalize Database
        # ────────────────────────────────────────────────────────────────────
        
        println("="^70)
        println("[6/6] Finalizing...")
        _finalize_run(run_dir, status="completed")
        println("  ✓ Run marked as completed")
        
        # Catalog (if available)
        if isdefined(Main, :_append_to_catalog)
            _append_to_catalog(config, run_id, "completed", run_dir, base_dir=base_dir)
        end
        
    catch e
        println("\n❌ Simulation failed!")
        _finalize_run(run_dir, status="failed")
        if isdefined(Main, :_append_to_catalog)
            _append_to_catalog(config, run_id, "failed", run_dir, base_dir=base_dir)
        end
        rethrow(e)
    end
    
    # ────────────────────────────────────────────────────────────────────────
    # Finish
    # ────────────────────────────────────────────────────────────────────────
    
    println("\nSimulation complete!")
    println("  Data saved in: $run_dir")
    println("="^70)
    
    return state, run_id, run_dir
end

# ============================================================================
# PART 5: TN Algorithm-Specific Runners
# ============================================================================

function _run_dmrg_simulation(state, solver, options, n_sweeps, run_dir)
    energies = Float64[]
    
    for sweep in 1:n_sweeps
        # Run DMRG sweep
        energy_right = dmrg_sweep(state, solver, options, :right)
        energy_left = dmrg_sweep(state, solver, options, :left)
        push!(energies, energy_left)
        
        # Get bond dimensions
        bond_dims = [size(tensor, 1) for tensor in state.mps.tensors]
        max_bond_dim = maximum(bond_dims)
        
        # Save data
        extra_data = Dict(
            "energy" => energy_left,
            "max_bond_dim" => max_bond_dim,
        )
        
        _save_mps_sweep(state, run_dir, sweep; extra_data=extra_data)
        
        # Print progress
        if sweep % 1 == 0
            println("Sweep $sweep: E = $energy_left, χ_max = $max_bond_dim")
        end
    end
    
    println("\nFinal Energy: $(energies[end])")
end

function _run_tdvp_simulation(state, solver, options, n_sweeps, run_dir)
    current_time = 0.0
    
    for sweep in 1:n_sweeps
        # Run TDVP sweep
        tdvp_sweep(state, solver, options, :right)
        tdvp_sweep(state, solver, options, :left)
        
        # Update time
        current_time += options.dt
        
        # Get bond dimensions
        bond_dims = [size(tensor, 1) for tensor in state.mps.tensors]
        max_bond_dim = maximum(bond_dims)
        
        # Save data
        extra_data = Dict(
            "time" => current_time,
            "max_bond_dim" => max_bond_dim,
        )
        
        _save_mps_sweep(state, run_dir, sweep; extra_data=extra_data)
        
        # Print progress
        if sweep % 10 == 0
            println("Sweep $sweep: t = $current_time, χ_max = $max_bond_dim")
        end
    end
    
    println("\nTDVP simulation complete")
    println("Final time: $current_time")
end

# ============================================================================
# PART 6: ED Simulation Handler
# ============================================================================

function _run_ed_simulation(config; base_dir="data", force_rerun=false)
    
    algorithm = config["algorithm"]["type"]
    
    println("="^70)
    println("Starting ED Simulation: $(uppercase(algorithm))")
    println("="^70)
    
    # ════════════════════════════════════════════════════════════════════════
    # DEDUPLICATION CHECK
    # ════════════════════════════════════════════════════════════════════════
    
    println("\n[1/5] Checking for existing runs...")
    
    if !force_rerun
        existing = _get_completed_run(config, base_dir=base_dir)
        
        if existing !== nothing
            println("="^70)
            println("✓ SIMULATION ALREADY COMPLETED")
            println("="^70)
            println("  Run ID: $(existing["run_id"])")
            println("  Path:   $(existing["run_dir"])")
            println("")
            println("  To force re-run, use: force_rerun=true")
            println("="^70)
            
            return nothing, existing["run_id"], existing["run_dir"]
        end
        
        println("  No completed run found. Proceeding...")
    else
        println("  force_rerun=true. Skipping deduplication check...")
    end
    
    # ════════════════════════════════════════════════════════════════════════
    # DATABASE SETUP
    # ════════════════════════════════════════════════════════════════════════
    
    println("\n[2/5] Setting up database...")
    
    run_id, run_dir = _setup_run_directory(config, base_dir=base_dir)
    println("  ✓ Run ID: $run_id")
    println("  ✓ Data directory: $run_dir")
    
    # ════════════════════════════════════════════════════════════════════════
    # BUILD HAMILTONIAN
    # ════════════════════════════════════════════════════════════════════════
    
    println("\n[3/5] Building Hamiltonian...")
    
    H = build_H_from_config(config)
    D = size(H, 1)
    println("  ✓ Hamiltonian: $(D) × $(D)")
    println("  ✓ Sparsity: $(round(100 * nnz(H) / D^2, digits=2))%")
    
    # ════════════════════════════════════════════════════════════════════════
    # RUN SIMULATION
    # ════════════════════════════════════════════════════════════════════════
    
    println("\n[4/5] Running simulation...")
    println("="^70)
    
    result = nothing
    
    try
        if algorithm == "ed_spectrum"
            result = _run_ed_spectrum_simulation(H, config, run_dir)
            
        elseif algorithm == "ed_time_evolution"
            result = _run_ed_time_evolution_simulation(H, config, run_dir)
        end
        
        # ════════════════════════════════════════════════════════════════════
        # FINALIZE
        # ════════════════════════════════════════════════════════════════════
        
        println("="^70)
        println("[5/5] Finalizing...")
        _finalize_run(run_dir, status="completed")
        println("  ✓ Run marked as completed")
        
        # Catalog (if available)
        if isdefined(Main, :_append_to_catalog)
            _append_to_catalog(config, run_id, "completed", run_dir, base_dir=base_dir)
        end
        
    catch e
        println("\n❌ Simulation failed!")
        _finalize_run(run_dir, status="failed")
        if isdefined(Main, :_append_to_catalog)
            _append_to_catalog(config, run_id, "failed", run_dir, base_dir=base_dir)
        end
        rethrow(e)
    end
    
    println("\nSimulation complete!")
    println("  Data saved in: $run_dir")
    println("="^70)
    
    return result, run_id, run_dir
end

# ============================================================================
# PART 7: ED Algorithm-Specific Runners
# ============================================================================

function _run_ed_spectrum_simulation(H::AbstractMatrix, config::Dict, run_dir::String)
    algo = config["algorithm"]
    
    n_states = get(algo, "n_states", nothing)
    use_sparse = get(algo, "use_sparse", true)
    
    D = size(H, 1)
    
    # Diagonalize
    if n_states === nothing || n_states >= D
        println("  Solving full spectrum (D = $D)...")
        energies, states = solve_full_spectrum(H)
    else
        println("  Solving for $n_states lowest states (D = $D)...")
        energies, states = solve_spectrum(H, n_states, use_sparse=use_sparse)
    end
    
    println("  ✓ Diagonalization complete")
    println("    Ground state energy: $(energies[1])")
    if length(energies) >= 2
        println("    Spectral gap: $(energies[2] - energies[1])")
    end
    println("    States computed: $(length(energies))")
    
    # Save
    println("\n  Saving results...")
    _save_ed_spectrum(energies, states, run_dir)
    println("  ✓ Results saved to results.jld2")
    
    return Dict(
        :energies => energies,
        :states => states,
        :ground_energy => energies[1],
        :gap => length(energies) >= 2 ? energies[2] - energies[1] : nothing
    )
end

function _run_ed_time_evolution_simulation(H::AbstractMatrix, config::Dict, run_dir::String)
    algo = config["algorithm"]
    
    dt = algo["dt"]
    n_steps = algo["n_steps"]
    n_states_evol = get(algo, "n_states", nothing)
    
    # Build initial state
    println("  Building initial state...")
    psi0 = build_state_from_config(config)
    D = length(psi0)
    println("  ✓ Initial state: D = $D")
    
    # Prepare time evolution
    println("\n  Preparing time evolution (diagonalizing H)...")
    setup = prepare_time_evolution(H, psi0, n_states=n_states_evol)
    info = get_time_evolution_info(setup)
    println("  ✓ Diagonalization complete")
    println("    Eigenstates used: $(info[:n_states_used])")
    println("    Completeness: $(round(info[:completeness] * 100, digits=2))%")
    
    # Save initial state
    println("\n  Saving initial state (t = 0)...")
    _save_ed_step(psi0, run_dir, 0, extra_data=Dict("time" => 0.0))
    
    # Time evolution loop
    println("\n  Running time evolution...")
    println("  dt = $dt, n_steps = $n_steps, total time = $(dt * n_steps)")
    println("="^70)
    
    for step in 1:n_steps
        current_time = step * dt
        
        psi_t = evolve_to_time(setup, current_time)
        
        extra_data = Dict("time" => current_time)
        _save_ed_step(psi_t, run_dir, step, extra_data=extra_data)
        
        if step % max(1, n_steps ÷ 10) == 0 || step == n_steps
            println("  Step $step/$n_steps: t = $(round(current_time, digits=4))")
        end
    end
    
    final_time = n_steps * dt
    println("\n  ✓ Time evolution complete")
    println("    Final time: $final_time")
    println("    Steps saved: $(n_steps + 1) (including t=0)")
    
    return Dict(
        :final_time => final_time,
        :n_steps => n_steps,
        :dt => dt,
        :setup => setup
    )
end