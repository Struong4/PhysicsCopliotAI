using Pkg
Pkg.activate(@__DIR__)
using TNCodebase

# open query browser
#open_query_browser()

#open_query_builder()

results = query_catalog(
    status="completed",
    system_type="spin",
    N_lt=12,
    algorithm="ed_time_evolution",
    state_kind="prebuilt"
)

display_results(results)