using Pkg
Pkg.activate(joinpath(@__DIR__, "..",".."))

using TNCodebase
using JSON

# ============================================================================
# LOAD CONFIGURATION
# ============================================================================

config_file = joinpath(@__DIR__, "ed_time_evolution_analysis.json")
config = JSON.parsefile(config_file)

# Specify data directory relative to package root
data_dir = joinpath(@__DIR__, "..","..","data")
# Specify observable directory relative to package root
obs_dir = joinpath(@__DIR__, "..","..","data_obs")

obs_run_id, obs_run_dir = run_observable_calculation_from_config(
    config, 
    base_dir=data_dir,
    obs_base_dir=obs_dir
)

