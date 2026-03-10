using Pkg
Pkg.activate(dirname(@__DIR__))
using TNCodebase

# open query browser
build_query("sim", base_dir="data")

#results = query("sim", 
#    status="completed",
#    system_type="spin",
#    N_lte=12,
#    algorithm="ed_spectrum",
#    model_name="heisenberg"
#)

#display_results(results)