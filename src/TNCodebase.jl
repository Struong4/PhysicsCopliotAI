module TNCodebase

# ============================================================================
# CORE
# ============================================================================
include(joinpath(@__DIR__, "Core", "types.jl"))
export MPS, MPO, Environment, DMRGOptions, TDVPOptions

include(joinpath(@__DIR__, "Core", "site.jl"))
export spin_ops, boson_ops, BosonSite, SpinSite

include(joinpath(@__DIR__, "Core", "states.jl"))
export MPSState

include(joinpath(@__DIR__, "Core", "fsm.jl"))
export FiniteRangeCoupling, ExpChannelCoupling, PowerLawCoupling, Field,
       BosonOnly, SpinBosonInteraction, SpinFSMPath, SpinBosonFSMPath,
       build_FSM

# ============================================================================
# BUILDERS (TN)
# ============================================================================
include(joinpath(@__DIR__, "Builders", "mpobuilder.jl"))
export build_mpo

include(joinpath(@__DIR__, "Builders", "mpsbuilder.jl"))
export product_state, random_state

include(joinpath(@__DIR__, "Builders", "modelbuilder.jl"))
export build_mpo_from_config

include(joinpath(@__DIR__, "Builders", "statebuilder.jl"))
export build_mps_from_config

# ============================================================================
# TENSOR OPERATIONS
# ============================================================================
include(joinpath(@__DIR__, "TensorOps", "canonicalization.jl"))
export make_canonical, is_left_orthogonal, is_right_orthogonal, is_orthogonal

include(joinpath(@__DIR__, "TensorOps", "environment.jl"))

include(joinpath(@__DIR__, "TensorOps", "decomposition.jl"))
export svd_truncate, entropy, truncation_error

# ============================================================================
# ALGORITHMS (TN)
# ============================================================================
include(joinpath(@__DIR__, "Algorithms", "solvers.jl"))
export LanczosSolver, KrylovExponential

include(joinpath(@__DIR__, "Algorithms", "dmrg.jl"))
export dmrg_sweep

include(joinpath(@__DIR__, "Algorithms", "tdvp.jl"))
export tdvp_sweep

# ============================================================================
# ANALYSIS (TN) - INCLUDE FIRST to define function names
# ============================================================================
include(joinpath(@__DIR__, "Analysis", "contractions.jl"))
include(joinpath(@__DIR__, "Analysis", "core.jl"))
include(joinpath(@__DIR__, "Analysis", "correlations.jl"))
include(joinpath(@__DIR__, "Analysis", "entanglement.jl"))
include(joinpath(@__DIR__, "Analysis", "energy.jl"))

# ============================================================================
# ED (EXACT DIAGONALIZATION) - INCLUDE AFTER to add methods
# ============================================================================
include(joinpath(@__DIR__, "ED", "ed_basis.jl"))
include(joinpath(@__DIR__, "ED", "ed_operators.jl"))
include(joinpath(@__DIR__, "ED", "ed_terms.jl"))
include(joinpath(@__DIR__, "ED", "ed_hamiltonian.jl"))
include(joinpath(@__DIR__, "ED", "ed_models.jl"))
include(joinpath(@__DIR__, "ED", "ed_solver.jl"))
include(joinpath(@__DIR__, "ED", "ed_states.jl"))
include(joinpath(@__DIR__, "ED", "ed_observables.jl"))

# ============================================================================
# EXPORTS - Shared function names (multiple dispatch handles TN vs ED)
# ============================================================================
# These work for BOTH TN (MPS) and ED (state vector):
export single_site_expectation      # TN: (site, op, mps) | ED: (site, op, psi, N, S)
export subsystem_expectation_sum    # TN: (op, mps, l, m) | ED: (op, psi, l, m, N, S)
export two_site_expectation         # TN: (i, op_i, j, op_j, mps) | ED: (i, op_i, j, op_j, psi, N, S)
export correlation_function         # TN: (i, j, op, mps) | ED: (i, j, op, psi, N, S)
export connected_correlation        # TN: (i, j, op, mps) | ED: (i, j, op, psi, N, S)
export entanglement_entropy         # TN: (bond, mps) | ED: (cut, psi, N, d)
export entanglement_spectrum        # TN: (bond, mps) | ED: (cut, psi, N, d)
export energy_expectation           # TN: (mps, ham_mpo) | ED: (psi, H_sparse)
export energy_variance              # TN: (mps, ham_mpo) | ED: (psi, H_sparse)
export inner_product                # TN: (mps) or (mps1, mps2) | ED: (psi)
export overlap                      # TN: (mps1, mps2) | ED: (psi1, psi2)
export fidelity                     # ED only but could add TN

# ED-only exports (no TN equivalent)
export expectation_value_all_sites, correlation_matrix, all_entanglement_entropies
export survival_probability, loschmidt_echo
export single_site_expectation_sb, correlation_function_sb, correlation_matrix_sb
export entanglement_entropy_sb, entanglement_spectrum_sb
export boson_number, boson_distribution, boson_field_expectation, boson_spin_entanglement
export measure_observables

# ED infrastructure
export spin_basis_states, spinboson_basis_states, basis_state_to_index, index_to_basis_state
export spin_matrices, boson_matrices, embed_operator, embed_two_site
export embed_boson_operator, embed_spinboson_operator
export build_onsite_term, build_twobody_term, build_longrange_term
export build_boson_term, build_spinboson_coupling
export build_spin_hamiltonian, build_spinboson_hamiltonian
export build_H_from_config
export ed_spectrum, ed_ground_state, ed_time_evolution, ed_thermal_state
export build_ed_state_from_config, ed_product_state, ed_random_state
export ed_superposition_state, ed_neel_state, ed_domain_wall_state

# ============================================================================
# DATABASE
# ============================================================================
include(joinpath(@__DIR__, "Database", "database_utils.jl"))
export load_mps_sweep, load_mps_at_time, list_times
export load_ed_spectrum, load_ed_step, load_ed_at_time, list_ed_times
export is_ed_algorithm, is_tn_algorithm

include(joinpath(@__DIR__, "Database", "database_observables_utils.jl"))
export load_observable_sweep, load_all_observable_results
export find_observables_for_simulation, observable_already_calculated
export find_observable_runs_by_config, get_latest_observable_run_for_config

include(joinpath(@__DIR__, "Database", "database_catalog.jl"))

include(joinpath(@__DIR__, "Database", "query_catalog.jl"))
export query_catalog, display_results, display_results_compact
export get_run_ids, get_run_dirs, load_config
export list_available_models, list_available_algorithms
export catalog_summary, open_query_browser, open_query_builder

# ════════════════════════════════════════════════════════════════════════════
# NEW: Observable Catalog System
# ════════════════════════════════════════════════════════════════════════════
include(joinpath(@__DIR__, "Database", "database_observables_catalog.jl"))

include(joinpath(@__DIR__, "Database", "query_observables_catalog.jl"))
export query_observables, display_observable_results, display_observable_results_compact
export get_observable_run_ids, get_observable_run_dirs, load_observable_config
export list_observable_types, list_observable_algorithms
export observables_catalog_summary, get_observables_for_simulation
export compare_observables_across_algorithms
export open_observable_query_builder

# ════════════════════════════════════════════════════════════════════════════
# UNIFIED QUERY INTERFACE (Recommended API)
# ════════════════════════════════════════════════════════════════════════════
# Use these unified functions that work for both simulations and observables:
#
#   query("sim", ...)              # Query simulations
#   query("obs", ...)              # Query observables
#   display_results(results)       # Display any results
#   display_results_compact(...)   # Compact display
#   get_run_ids(results)           # Extract IDs from any results
#   get_run_dirs(results)          # Extract directories
#   load_config(result)            # Load config from any result
#   catalog_summary("sim"|"obs")   # Show catalog stats
#   build_query("sim"|"obs")       # Open HTML query builder
#   open_query(...)                # Alias for build_query
#
# ════════════════════════════════════════════════════════════════════════════

include(joinpath(@__DIR__, "Database", "query_builder.jl"))
export query                       # 🌟 Main query function
export display_results             # 🌟 Display results (unified)
export display_results_compact     # 🌟 Compact display (unified)
export get_run_ids                 # 🌟 Extract IDs (unified)
export get_run_dirs                # 🌟 Extract directories (unified)
export load_config                 # 🌟 Load config (unified)
export catalog_summary             # 🌟 Catalog stats (unified)
export build_query, open_query     # 🌟 HTML query builder (unified)

# ============================================================================
# RUNNERS
# ============================================================================
include(joinpath(@__DIR__, "Runners", "run_simulation.jl"))
export build_solver_from_config, build_options_from_config, run_simulation_from_config

include(joinpath(@__DIR__, "Runners", "run_Observable.jl"))
export run_observable_calculation_from_config, run_observable_from_run_id, load_observable_timeseries

end