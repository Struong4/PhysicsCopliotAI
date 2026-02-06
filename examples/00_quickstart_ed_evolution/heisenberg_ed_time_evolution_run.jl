#!/usr/bin/env julia
# ============================================================================
# Heisenberg Model: ED Time Evolution Example
# ============================================================================
#
# This script demonstrates exact time evolution of a quantum state under
# the Heisenberg Hamiltonian.
#
# USAGE:
#   julia ed_time_evolution_run.jl
#
# OUTPUT:
#   - Time-evolved quantum state at each time step
#   - Total evolution time: dt × n_steps = 0.05 × 200 = 10.0
#   - Data saved to TNCodebase/data/ed_time_evolution/
#
# ============================================================================

using Pkg
Pkg.activate("../../..")  # Activate TNCodebase from examples directory

using TNCodebase
using JSON

println("="^70)
println("Heisenberg Model: ED Time Evolution")
println("="^70)
println()

# ============================================================================
# Load Configuration
# ============================================================================

config_file = "ed_time_evolution_config.json"
config = JSON.parsefile(config_file)

println("📋 Configuration loaded from: $config_file")
println()
println("   System: $(config["system"]["type"]) chain")
println("   N sites: $(config["system"]["N"])")
println("   Model: $(config["model"]["name"])")
println("   Initial state: $(config["state"]["name"]) ($(config["state"]["params"]["spin_direction"])-polarized)")
println()
println("⏱️  Time evolution:")
println("   Time step dt: $(config["algorithm"]["dt"])")
println("   Number of steps: $(config["algorithm"]["n_steps"])")
println("   Total time: $(config["algorithm"]["dt"] * config["algorithm"]["n_steps"])")
println()

# ============================================================================
# Run ED Time Evolution
# ============================================================================

println("🚀 Starting time evolution...")
println()

run_simulation_from_config(config, base_dir="../../data")

println()
println("="^70)
println("✅ Time evolution complete!")
println("="^70)
println()
println("📊 Next steps:")
println("   1. Query results: query(\"sim\", algorithm=\"ed_time_evolution\")")
println("   2. Load time series: load_ed_at_time(run_id, time)")
println("   3. Calculate observables at each time step")
println("   4. Plot magnetization dynamics")
println()
