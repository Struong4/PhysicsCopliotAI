using Pkg
Pkg.activate(@__DIR__)
using TNCodebase

# open query browser
#build_query("sim", base_dir="data")

results = query("sim", 
    status="completed",
    system_type="spin",
    algorithm="ed_time_evolution",
    model_name="heisenberg"
)

display_results(results)