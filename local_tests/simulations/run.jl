using Pkg
Pkg.activate(joinpath(@__DIR__, "..",".."))

using TNCodebase
using JSON

# ============================================================================
# LOAD CONFIGURATION
# ============================================================================

config_file = joinpath(@__DIR__, "simulation_config_dmrg.json")
config = JSON.parsefile(config_file)

# ============================================================================
# RUN SIMULATION
# ============================================================================


# Specify data directory relative to package root
data_dir = joinpath(@__DIR__, "..","..","data")

# Run simulation - returns final state, run_id, and run_directory
state, run_id, run_dir = run_simulation_from_config(config, base_dir=data_dir)

