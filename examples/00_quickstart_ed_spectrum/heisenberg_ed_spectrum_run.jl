#!/usr/bin/env julia
# ============================================================================
# Heisenberg Model: ED Spectrum Example
# ============================================================================
#
# This script demonstrates exact diagonalization to compute the FULL
# eigenspectrum of the Heisenberg model.
#
# USAGE:
#   julia ed_spectrum_run.jl
#
# OUTPUT:
#   - All eigenvalues and eigenvectors
#   - Ground state energy
#   - Spectral gap
#   - Data saved to TNCodebase/data/ed_spectrum/
#
# ============================================================================

using Pkg
Pkg.activate("../../..")  # Activate TNCodebase from examples directory

using TNCodebase
using JSON

println("="^70)
println("Heisenberg Model: ED Spectrum Calculation")
println("="^70)
println()

# ============================================================================
# Load Configuration
# ============================================================================

config_file = "ed_spectrum_config.json"
config = JSON.parsefile(config_file)

println("📋 Configuration loaded from: $config_file")
println()
println("   System: $(config["system"]["type"]) chain")
println("   N sites: $(config["system"]["N"])")
println("   Model: $(config["model"]["name"])")
println("   Hilbert space dimension: 2^$(config["system"]["N"]) = $(2^config["system"]["N"])")
println()

# ============================================================================
# Run ED Spectrum Calculation
# ============================================================================

println("🚀 Starting exact diagonalization...")
println()

run_simulation_from_config(config, base_dir="../../data")

println()
println("="^70)
println("✅ ED Spectrum calculation complete!")
println("="^70)
println()
println("📊 Next steps:")
println("   1. Query results: query(\"sim\", algorithm=\"ed_spectrum\")")
println("   2. Load spectrum: load_ed_spectrum(run_id)")
println("   3. Calculate observables on eigenstates")
println()
