# ============================================================================
# PART 1: Solver Builders
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
# PART 2: Options Builders
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
        error("Unknown algorithm type: $algorithm_type. Use 'dmrg' or 'tdvp'")
    end
end

# ============================================================================
# PART 3: Main Simulation Runner
# ============================================================================

"""
    run_simulation_from_config(config)

Main entry point: takes unified config, returns final state.

Builds:
1. Sites from system config
2. MPO from model config
3. MPS from state config
4. Runs algorithm with specified solver and options
"""

function run_simulation_from_config(config; base_dir="data", force_rerun=false)
    println("="^70)
    println("Starting Simulation from Config")
    println("="^70)

    # ════════════════════════════════════════════════════════════════════════
    # DEDUPLICATION CHECK (before anything else!)
    # ════════════════════════════════════════════════════════════════════════
    
    println("\n[0/6] Checking for existing runs...")
    
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
    
    println("\n[1/6] Setting up database...")
    
    # Setup run directory and initialize database
    run_id, run_dir = _setup_run_directory(config, base_dir=base_dir)
    println("  ✓ Run ID: $run_id")
    println("  ✓ Data directory: $run_dir")
    
    # ────────────────────────────────────────────────────────────────────────
    # Build System Components
    # ────────────────────────────────────────────────────────────────────────
    
    println("\n[2/6] Building system components...")
        
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
    
    println("\n[3/6] Parsing algorithm configuration...")
        
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
    
    println("\n[4/6] Running simulation...")
    println("="^70)
    
    try
        if config["algorithm"]["type"] == "dmrg"
            _run_dmrg_simulation(state, solver, options, n_sweeps, run_dir)
            
        elseif config["algorithm"]["type"] == "tdvp"
            _run_tdvp_simulation(state, solver, options, n_sweeps, run_dir)
            
        else
            error("Unknown algorithm: $(config["algorithm"]["type"])")
        end
        
        # ────────────────────────────────────────────────────────────────────
        # Finalize Database
        # ────────────────────────────────────────────────────────────────────
        
        println("="^70)
        println("[5/6] Finalizing database...")
        _finalize_run(run_dir, status="completed")
        println("  ✓ Run marked as completed")
        
        # ────────────────────────────────────────────────────────────────────
        # Append to Catalog
        # ────────────────────────────────────────────────────────────────────
        
        println("\n[6/6] Updating catalog...")
        _append_to_catalog(config, run_id, "completed", run_dir, base_dir=base_dir)
        
    catch e
        # If simulation fails, mark as failed and update catalog
        println("\n❌ Simulation failed!")
        _finalize_run(run_dir, status="failed")
        _append_to_catalog(config, run_id, "failed", run_dir, base_dir=base_dir)
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
# PART 4: Algorithm-Specific Runners
# ============================================================================

function _run_dmrg_simulation(state, solver, options, n_sweeps, run_dir)
    energies = Float64[]
    
    for sweep in 1:n_sweeps
        # ────────────────────────────────────────────────────────────────────
        # Run DMRG sweep
        # ────────────────────────────────────────────────────────────────────
        
        # Right sweep
        energy_right = dmrg_sweep(state, solver, options, :right)
        # Left sweep
        energy_left = dmrg_sweep(state, solver, options, :left)
        push!(energies, energy_left)
        
        # ────────────────────────────────────────────────────────────────────
        # Compute observables
        # ────────────────────────────────────────────────────────────────────
        
        # Get bond dimensions
        bond_dims = [size(tensor, 1) for tensor in state.mps.tensors]
        max_bond_dim = maximum(bond_dims)
        
        # ────────────────────────────────────────────────────────────────────
        # Save data
        # ────────────────────────────────────────────────────────────────────
        
        extra_data = Dict(
            "energy" => energy_left,
            "max_bond_dim" => max_bond_dim,
        )
        
        _save_mps_sweep(state, run_dir, sweep; extra_data=extra_data)
        
        # ────────────────────────────────────────────────────────────────────
        # Print progress
        # ────────────────────────────────────────────────────────────────────
        
        if sweep % 1 == 0
            println("Sweep $sweep: E = $energy_left, χ_max = $max_bond_dim")
        end
    end
    
    println("\nFinal Energy: $(energies[end])")
end

function _run_tdvp_simulation(state, solver, options, n_sweeps, run_dir)
    # Current time
    current_time = 0.0
    
    for sweep in 1:n_sweeps
        # ────────────────────────────────────────────────────────────────────
        # Run TDVP sweep
        # ────────────────────────────────────────────────────────────────────
        
        # Right sweep
        tdvp_sweep(state, solver, options, :right)
        
        # Left sweep
        tdvp_sweep(state, solver, options, :left)
        
        # Update time (one full sweep = one time step)
        current_time += options.dt
        
        # ────────────────────────────────────────────────────────────────────
        # Compute observables
        # ────────────────────────────────────────────────────────────────────
        
        # Get bond dimensions
        bond_dims = [size(tensor, 1) for tensor in state.mps.tensors]
        max_bond_dim = maximum(bond_dims)
        
        # ────────────────────────────────────────────────────────────────────
        # Save data
        # ────────────────────────────────────────────────────────────────────
        
        extra_data = Dict(
            "time" => current_time,
            "max_bond_dim" => max_bond_dim,
        )
        
        _save_mps_sweep(state, run_dir, sweep; extra_data=extra_data)
        
        # ────────────────────────────────────────────────────────────────────
        # Print progress
        # ────────────────────────────────────────────────────────────────────
        
        if sweep % 10 == 0
            println("Sweep $sweep: t = $current_time, χ_max = $max_bond_dim")
        end
    end
    
    println("\nTDVP simulation complete")
    println("Final time: $current_time")
end
