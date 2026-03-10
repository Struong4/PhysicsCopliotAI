#!/usr/bin/env julia
# ============================================================================
# PIPELINE SERVER STARTUP SCRIPT - TNSoftware Project
# ============================================================================
#
# Project Root: /home/nishan/PD_UMBC/Research/Software_Dev/TNSoftware
# Uses the TNCodebase module for all functionality
#
# USAGE:
#   cd /home/nishan/PD_UMBC/Research/Software_Dev/TNSoftware
#   julia server/start_server.jl
#
# ============================================================================

println("="^70)
println("TNSoftware Pipeline Server")
println("="^70)
println()

# ============================================================================
# PROJECT ROOT DETECTION
# ============================================================================

# This script is in the server/ subdirectory — project root is one level up
const PROJECT_ROOT = dirname(@__DIR__)

println("Project root: $PROJECT_ROOT")
println()

# Verify we're in the right place (only check source dirs, data dirs are created below)
required_dirs = ["src", "frontend"]
for dir in required_dirs
    path = joinpath(PROJECT_ROOT, dir)
    if !isdir(path)
        error("Expected directory not found: $path\nMake sure you're running from the TNSoftware root directory!")
    end
end

# ============================================================================
# CONFIGURATION - Data Directories
# ============================================================================

const FRONTEND_DIR = joinpath(PROJECT_ROOT, "frontend")
const DATA_DIR = joinpath(PROJECT_ROOT, "data")
const OBSERVABLES_DIR = joinpath(PROJECT_ROOT, "data_obs")

println("Configuration:")
println("  Source code:   $(joinpath(PROJECT_ROOT, "src"))")
println("  Frontend:      $FRONTEND_DIR")
println("  Data:          $DATA_DIR")
println("  Observables:   $OBSERVABLES_DIR")
println()

# Create data directories if they don't exist
mkpath(DATA_DIR)
mkpath(OBSERVABLES_DIR)

# ============================================================================
# LOAD DEPENDENCIES
# ============================================================================

println("Loading dependencies...")

# Activate the project environment
using Pkg
Pkg.activate(PROJECT_ROOT)

# Load required packages
using HTTP
using JSON
using Dates
using JLD2
using SHA
using LinearAlgebra
using SparseArrays
using Printf

# ============================================================================
# LOAD TNCodebase MODULE
# ============================================================================

println()
println("Loading TNCodebase module...")
println("-"^70)

# Load the main module (this loads everything in correct order)
using TNCodebase

println("-"^70)
println()
println("✓ All modules loaded successfully!")
println()

# ============================================================================
# SET GLOBAL CONFIGURATION FOR SERVER
# ============================================================================

# Make these available to pipeline_server.jl
global const SERVER_DATA_DIR = DATA_DIR
global const SERVER_OBSERVABLES_DIR = OBSERVABLES_DIR
global const SERVER_PROJECT_ROOT = PROJECT_ROOT
global const SERVER_FRONTEND_DIR = FRONTEND_DIR

# ============================================================================
# LOAD SERVER
# ============================================================================

server_script = joinpath(PROJECT_ROOT, "server", "pipeline_server.jl")
if !isfile(server_script)
    error("pipeline_server.jl not found at: $server_script\n" *
          "Make sure pipeline_server.jl is in the server/ directory!")
end

include(server_script)

# ============================================================================
# START SERVER
# ============================================================================

println("="^70)
println("Starting HTTP server...")
println("="^70)
println()
println("Server will:")
println("  • Serve GUI from:  http://127.0.0.1:8080")
println("  • Load config from: $FRONTEND_DIR/config_builder.html")
println("  • Save data to:     $DATA_DIR")
println("  • Save obs to:      $OBSERVABLES_DIR")
println()
println("Press Ctrl+C to stop server")
println("="^70)
println()

# ============================================================================
# AUTO-OPEN BROWSER
# ============================================================================

"""
Open default browser automatically (cross-platform)
"""
function open_browser(url::String; delay::Real=1.5)
    @async begin
        sleep(delay)  # Wait for server to be ready
        
        try
            if Sys.islinux()
                run(`xdg-open $url`)
            elseif Sys.isapple()
                run(`open $url`)
            elseif Sys.iswindows()
                run(`cmd /c start $url`)
            else
                @warn "Could not detect OS. Please open $url manually."
            end
            println("\n✓ Opened browser at $url")
        catch e
            @warn "Could not auto-open browser. Please open $url manually."
        end
    end
end

# Open browser after a short delay (gives server time to start)
open_browser("http://127.0.0.1:8080")

start_server(8080, "127.0.0.1")