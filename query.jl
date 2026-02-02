using Pkg
Pkg.activate(@__DIR__)
using TNCodebase

# open query browser
#open_query_browser()

open_query_builder()

#results = query_catalog(
#    status="completed",
#    system_type="spin",
#    N_lte=11,
#    algorithm="tdvp",
#    model_name="transverse_field_ising",
#    state_kind="prebuilt"
#)

#display_results(results)