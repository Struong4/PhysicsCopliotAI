# ============================================================================
# UNIFIED QUERY INTERFACE
# ============================================================================
#
# Provides unified API for querying both simulation and observable catalogs.
# Users interact with single consistent functions regardless of catalog type.
#
# USAGE:
#   results = query("sim", algorithm="dmrg")
#   results = query("obs", observable_type="entanglement")
#   display_results(results)   # Works for both!
#
# ============================================================================

using Dates
using JSON

# ============================================================================
# KEYWORD SETS
# ============================================================================

const _SIM_KEYS = Set(["sim", "simulation", "run", "runs", "simulations"])
const _OBS_KEYS = Set(["obs", "observable", "observables", "analysis"])
_normalize_kind(kind::AbstractString) = lowercase(strip(kind))

# ============================================================================
# UNIFIED QUERY FUNCTION
# ============================================================================

function query(kind::AbstractString = "sim"; kwargs...)
    k = _normalize_kind(kind)
    
    if k in _SIM_KEYS
        results = query_catalog(; kwargs...)
        for r in results
            r["_query_type"] = "simulation"
        end
        return results
        
    elseif k in _OBS_KEYS
        results = query_observables(; kwargs...)
        for r in results
            r["_query_type"] = "observable"
        end
        return results
        
    else
        error(
            "Unknown query kind: \"$kind\"\n\n" *
            "Available options:\n" *
            "  Simulations: sim, simulation, run, runs\n" *
            "  Observables: obs, observable, observables, analysis\n"
        )
    end
end

# ============================================================================
# UNIFIED DISPLAY AND HELPER FUNCTIONS  
# ============================================================================
# Note: These call the underlying specialized functions from query_catalog.jl
# and query_observables_catalog.jl after detecting type from metadata.
# ============================================================================

function _unified_display_results(results::Vector{Dict})
    if isempty(results)
        println("No results found.")
        return
    end
    
    query_type = get(results[1], "_query_type", nothing)
    
    # Remove metadata tag before displaying
    clean_results = [Dict(k => v for (k, v) in r if k != "_query_type") for r in results]
    
    if query_type == "simulation"
        # Call the original display_results from query_catalog.jl
        # This function is already in the module namespace
        for r in clean_results
            _display_single_result(r)
        end
        println("\nTotal: $(length(clean_results)) run(s)")
        
    elseif query_type == "observable"
        # Call display_observable_results from query_observables_catalog.jl
        display_observable_results(clean_results)
        
    else
        error("Results must come from query() function")
    end
end

function _unified_display_results_compact(results::Vector{Dict})
    if isempty(results)
        println("No results found.")
        return
    end
    
    query_type = get(results[1], "_query_type", nothing)
    clean_results = [Dict(k => v for (k, v) in r if k != "_query_type") for r in results]
    
    if query_type == "simulation"
        display_results_compact(clean_results)
    elseif query_type == "observable"
        display_observable_results_compact(clean_results)
    else
        error("Results must come from query() function")
    end
end

function _unified_get_run_ids(results::Vector{Dict})
    if isempty(results)
        return String[]
    end
    
    query_type = get(results[1], "_query_type", nothing)
    
    if query_type == "simulation"
        return get_run_ids(results)
    elseif query_type == "observable"
        return get_observable_run_ids(results)
    else
        error("Results must come from query() function")
    end
end

function _unified_get_run_dirs(results::Vector{Dict})
    if isempty(results)
        return String[]
    end
    
    query_type = get(results[1], "_query_type", nothing)
    
    if query_type == "simulation"
        return get_run_dirs(results)
    elseif query_type == "observable"
        return get_observable_run_dirs(results)
    else
        error("Results must come from query() function")
    end
end

function _unified_load_config(result::Dict)
    query_type = get(result, "_query_type", nothing)
    
    if query_type == "simulation"
        return load_config(result)
    elseif query_type == "observable"
        return load_observable_config(result)
    else
        error("Result must come from query() function")
    end
end

function _unified_catalog_summary(kind::AbstractString = "sim";
                                 base_dir::Union{Nothing,AbstractString} = nothing,
                                 obs_base_dir::Union{Nothing,AbstractString} = nothing)
    k = _normalize_kind(kind)
    
    if k in _SIM_KEYS
        sim_base = base_dir === nothing ? "data" : base_dir
        return catalog_summary(base_dir=sim_base)
    elseif k in _OBS_KEYS
        obs_base = obs_base_dir === nothing ? "observables" : obs_base_dir
        return observables_catalog_summary(obs_base_dir=obs_base)
    else
        error("Unknown kind: \"$kind\". Use \"sim\" or \"obs\"")
    end
end

# ============================================================================
# HTML QUERY BUILDER
# ============================================================================

function build_query(kind::AbstractString = "sim";
                     base_dir::Union{Nothing,AbstractString} = nothing,
                     kwargs...)
    
    k = _normalize_kind(kind)
    
    if k in _SIM_KEYS
        sim_base = base_dir === nothing ? "data" : base_dir
        println("╔═══════════════════════════════════════════════════════╗")
        println("║   Opening SIMULATION Query Builder                   ║")
        println("╚═══════════════════════════════════════════════════════╝")
        println("  Catalog: $sim_base/run_catalog.jsonl\n")
        return open_query_builder(; base_dir = sim_base, kwargs...)
    end
    
    if k in _OBS_KEYS
        obs_base = base_dir === nothing ? "observables" : base_dir
        println("╔═══════════════════════════════════════════════════════╗")
        println("║   Opening OBSERVABLE Query Builder                   ║")
        println("╚═══════════════════════════════════════════════════════╝")
        println("  Catalog: $obs_base/observables_catalog.jsonl\n")
        return open_observable_query_builder(; obs_base_dir = obs_base, kwargs...)
    end
    
    error("Unknown query kind: \"$kind\". Use \"sim\" or \"obs\"")
end

open_query(args...; kwargs...) = build_query(args...; kwargs...)