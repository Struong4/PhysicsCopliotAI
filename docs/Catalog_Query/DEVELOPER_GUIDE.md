# DEVELOPER GUIDE - Catalog & Query System

## 📋 Table of Contents
1. [Overview](#overview)
2. [System Architecture](#system-architecture)
3. [Code Organization](#code-organization)
4. [Adding New Features](#adding-new-features)
5. [Extending Query Filters](#extending-query-filters)
6. [Adding New Observable Types](#adding-new-observable-types)
7. [Custom Catalog Fields](#custom-catalog-fields)
8. [Testing](#testing)
9. [Debugging](#debugging)
10. [Best Practices](#best-practices)

---

## Overview

This guide is for **developers** who want to understand, maintain, or extend the catalog and query system.

### Who This is For

- Contributors adding new algorithms
- Developers adding new observable types
- Maintainers debugging catalog issues
- Researchers extending query capabilities

### Prerequisites

You should understand:
- Julia programming
- JSON data structures
- Basic database concepts
- TNCodebase simulation workflow

---

## System Architecture

### Component Overview

```
┌──────────────────────────────────────────────────────────────────┐
│                     TNCodebase Catalog/Query System                │
└──────────────────────────────────────────────────────────────────┘

┌─────────────────┐      ┌──────────────────┐      ┌──────────────┐
│   Simulations   │      │ Observable Calcs │      │    Queries   │
│   (Runners)     │      │  (Observables)   │      │   (Users)    │
└────────┬────────┘      └────────┬─────────┘      └──────┬───────┘
         │                        │                        │
         │ writes                 │ writes                 │ reads
         ↓                        ↓                        ↓
  ┌─────────────┐          ┌──────────────┐        ┌─────────────┐
  │   Catalog   │          │  Observable  │        │   Query     │
  │   Builder   │          │   Catalog    │        │  Functions  │
  │             │          │   Builder    │        │             │
  └──────┬──────┘          └──────┬───────┘        └──────┬──────┘
         │                        │                        │
         │ appends                │ appends                │ filters
         ↓                        ↓                        ↓
  ┌─────────────────────────────────────────────────────────────┐
  │                  Catalog Files (JSONL)                       │
  │  • run_catalog.jsonl (simulations)                          │
  │  • observables_catalog.jsonl (observables)                  │
  └─────────────────────────────────────────────────────────────┘
```

### Data Flow

**Write Path (Cataloging):**
```
Simulation completes
    ↓
_finalize_run() called
    ↓
_extract_catalog_entry() builds metadata
    ↓
_append_to_catalog() writes to JSONL
    ↓
Catalog file updated
```

**Read Path (Querying):**
```
query("sim", filters...) called
    ↓
_load_catalog() reads JSONL
    ↓
_filter_entries() applies filters
    ↓
_tag_results() adds metadata
    ↓
Returns results to user
```

---

## Code Organization

### File Structure

```
src/Database/
│
├── database_catalog.jl                # Simulation catalog
│   ├── _extract_core()
│   ├── _extract_algorithm_params()
│   ├── _extract_model()
│   ├── _extract_state()
│   ├── _extract_results_summary()
│   ├── _extract_catalog_entry()
│   ├── _append_to_catalog()
│   └── _load_catalog()
│
├── database_observables_catalog.jl    # Observable catalog
│   ├── _extract_simulation_info_for_observable()
│   ├── _extract_observable_info()
│   ├── _extract_analysis_params()
│   ├── _extract_observable_catalog_entry()
│   ├── _append_to_observables_catalog()
│   └── _load_observables_catalog()
│
├── query_catalog.jl                   # Simulation queries
│   ├── query_catalog()
│   ├── display_results()
│   ├── get_run_ids()
│   └── open_query_builder()
│
├── query_observables_catalog.jl       # Observable queries
│   ├── query_observables()
│   ├── display_observable_results()
│   ├── get_observable_run_ids()
│   └── open_observable_query_builder()
│
└── query_builder.jl                   # Unified interface
    ├── query() [unified]
    ├── display_results() [unified]
    ├── get_run_ids() [unified]
    ├── build_query()
    └── catalog_summary()
```

### Key Design Patterns

**1. Extraction Pattern**

All catalog building uses extraction functions:
```julia
function _extract_X(config::Dict)
    # Parse config
    # Extract relevant fields
    # Return Dict with standardized structure
end
```

**2. Conditional Extraction**

Some fields are optional (e.g., initial state):
```julia
function _extract_catalog_entry(config, ...)
    entry = Dict(...)
    
    # Only add state if present
    if haskey(config, "state")
        entry["state"] = _extract_state(config)
    end
    
    return entry
end
```

**3. Delegation Pattern**

Unified functions delegate to specialized ones:
```julia
function query(kind, ...)
    if kind in _SIM_KEYS
        return query_catalog(...)
    elseif kind in _OBS_KEYS
        return query_observables(...)
    end
end
```

**4. Metadata Tagging**

Results are tagged for auto-detection:
```julia
function query(kind, ...)
    results = query_catalog(...)
    for r in results
        r["_query_type"] = "simulation"  # Tag it!
    end
    return results
end
```

---

## Adding New Features

### Example: Add New Algorithm

**Scenario:** You've implemented a new algorithm `my_algorithm` and want it cataloged.

#### Step 1: Define Algorithm Parameters

```julia
# In algorithm runner file
function run_my_algorithm(config::Dict, run_dir::String)
    # Extract parameters
    my_param1 = config["algorithm"]["my_param1"]
    my_param2 = config["algorithm"]["options"]["my_param2"]
    
    # Run algorithm...
    
    # Save results
    save(joinpath(run_dir, "results.jld2"), 
         "my_result" => result_value)
end
```

#### Step 2: Add Metadata Extraction

```julia
# In database_catalog.jl
function _extract_algorithm_params(config::Dict)
    algo = config["algorithm"]["type"]
    params = Dict{String, Any}()
    
    if algo == "dmrg"
        # ... existing code ...
        
    elseif algo == "my_algorithm"  # ← Add this
        params["my_param1"] = config["algorithm"]["my_param1"]
        params["my_param2"] = config["algorithm"]["options"]["my_param2"]
    end
    
    return params
end
```

#### Step 3: Add Results Summary Extraction

```julia
# In database_catalog.jl
function _extract_results_summary(config::Dict, run_dir::String)
    algo = config["algorithm"]["type"]
    summary = Dict{String, Any}()
    
    metadata = JSON.parsefile(joinpath(run_dir, "metadata.json"))
    
    if algo == "dmrg"
        # ... existing code ...
        
    elseif algo == "my_algorithm"  # ← Add this
        summary["my_result"] = get(metadata, "my_result", nothing)
        summary["convergence"] = get(metadata, "convergence_flag", nothing)
    end
    
    return summary
end
```

#### Step 4: Test

```julia
# Create config
config = Dict(
    "system" => Dict("type" => "spin", "N" => 10),
    "model" => Dict("name" => "heisenberg", ...),
    "algorithm" => Dict(
        "type" => "my_algorithm",
        "my_param1" => 42,
        "options" => Dict("my_param2" => 3.14)
    )
)

# Run
run_simulation_from_config(config)

# Query
results = query("sim", algorithm="my_algorithm")
display_results(results)

# Check catalog entry
@assert results[1]["algorithm_params"]["my_param1"] == 42
@assert results[1]["algorithm_params"]["my_param2"] == 3.14
```

**Done!** Your algorithm is now fully cataloged and queryable.

---

## Extending Query Filters

### How Filtering Works

Current implementation in `query_catalog.jl`:

```julia
function query_catalog(; base_dir="data", filters...)
    # Load catalog
    entries = _load_catalog(base_dir=base_dir)
    
    # Apply filters
    for (key, value) in filters
        entries = _filter_by_key(entries, key, value)
    end
    
    return entries
end

function _filter_by_key(entries, key, value)
    # Handle comparison operators
    if endswith(String(key), "_gt")
        field = replace(String(key), "_gt" => "")
        return filter(e -> _get_nested(e, field) > value, entries)
        
    elseif endswith(String(key), "_gte")
        field = replace(String(key), "_gte" => "")
        return filter(e -> _get_nested(e, field) >= value, entries)
        
    # ... more operators ...
    
    else
        # Exact match
        return filter(e -> _get_nested(e, key) == value, entries)
    end
end
```

### Adding New Filter Types

**Example: Add regex matching**

```julia
# New operator: _matches (regex)
function _filter_by_key(entries, key, value)
    # ... existing operators ...
    
    elseif endswith(String(key), "_matches")
        field = replace(String(key), "_matches" => "")
        pattern = Regex(value)
        return filter(e -> occursin(pattern, _get_nested(e, field)), entries)
    
    # ... rest of function ...
end
```

**Usage:**
```julia
# Find all models with "ising" in name
results = query("sim", model_name_matches="ising")
# Matches: "transverse_field_ising", "long_range_ising", etc.
```

### Adding Custom Filter Logic

**Example: Filter by energy range**

```julia
# In query_catalog.jl
function query_catalog(; base_dir="data", 
                       energy_range=nothing,  # ← New parameter
                       filters...)
    entries = _load_catalog(base_dir=base_dir)
    
    # Custom energy range filter
    if energy_range !== nothing
        E_min, E_max = energy_range
        entries = filter(entries) do e
            if haskey(e, "results_summary") && 
               haskey(e["results_summary"], "ground_energy")
                E = e["results_summary"]["ground_energy"]
                return E_min <= E <= E_max
            end
            return false
        end
    end
    
    # Apply other filters
    for (key, value) in filters
        entries = _filter_by_key(entries, key, value)
    end
    
    return entries
end
```

**Usage:**
```julia
# Find runs with energy between -9 and -8
results = query("sim", 
    algorithm="dmrg",
    energy_range=(-9.0, -8.0)
)
```

---

## Adding New Observable Types

### Example: Custom Observable "Spin Current"

#### Step 1: Implement Observable Calculation

```julia
# In Observables/observable_spin_current.jl
function calculate_spin_current(state, params::Dict)
    # Extract parameters
    site = params["site"]
    
    # Calculate ⟨J_spin⟩ = i⟨S⁺ᵢS⁻ᵢ₊₁ - S⁻ᵢS⁺ᵢ₊₁⟩
    current = ...  # Implementation
    
    return current
end
```

#### Step 2: Register Observable Type

```julia
# In run_Observable.jl or observable dispatcher
OBSERVABLE_TYPES["spin_current"] = calculate_spin_current
```

#### Step 3: Catalog Extraction (Already Works!)

The observable catalog system automatically handles new types:

```julia
# Create observable config
obs_config = Dict(
    "simulation" => sim_config,
    "observable" => Dict(
        "type" => "spin_current",  # ← New type!
        "params" => Dict("site" => 5)
    ),
    "analysis" => Dict(...)
)

# Run
run_observable_calculation_from_config(obs_config)
```

The catalog entry will be:
```json
{
  "observable": {
    "type": "spin_current",
    "params": {"site": 5}
  },
  ...
}
```

#### Step 4: Query It

```julia
# Works immediately!
results = query("obs", observable_type="spin_current")
display_results(results)
```

**No catalog code changes needed** - the system is already generic!

---

## Custom Catalog Fields

### Adding Global Custom Fields

**Example: Add git commit hash to all runs**

```julia
# In database_catalog.jl
function _extract_catalog_entry(config, run_id, status, run_dir)
    entry = Dict{String, Any}(
        "run_id" => run_id,
        # ... existing fields ...
    )
    
    # Add git hash
    try
        git_hash = read(`git rev-parse HEAD`, String) |> strip
        entry["git_commit"] = git_hash
    catch
        entry["git_commit"] = "unknown"
    end
    
    return entry
end
```

Now all catalog entries include:
```json
{
  "run_id": "...",
  "git_commit": "a3f7b2c1...",
  ...
}
```

### Adding Algorithm-Specific Fields

**Example: Add DMRG convergence details**

```julia
function _extract_results_summary(config::Dict, run_dir::String)
    algo = config["algorithm"]["type"]
    summary = Dict{String, Any}()
    
    metadata = JSON.parsefile(joinpath(run_dir, "metadata.json"))
    
    if algo == "dmrg"
        summary["ground_energy"] = get(metadata, "final_energy", nothing)
        summary["bond_dim"] = get(metadata, "max_bond_dim", nothing)
        
        # ← Add detailed convergence info
        if haskey(metadata, "energy_history")
            summary["convergence"] = Dict(
                "final_change" => metadata["energy_history"][end] - 
                                 metadata["energy_history"][end-1],
                "sweeps_to_converge" => _count_convergence_sweeps(
                    metadata["energy_history"]
                )
            )
        end
    end
    
    return summary
end
```

### Querying Custom Fields

```julia
# Query by custom field
results = query("sim", 
    algorithm="dmrg",
    result_convergence_sweeps_to_converge_lt=30  # ← Nested access
)
```

---

## Testing

### Unit Tests for Catalog Building

```julia
# test/test_catalog.jl
using Test
using TNCodebase

@testset "Catalog Building" begin
    # Create test config
    config = Dict(
        "system" => Dict("type" => "spin", "N" => 10),
        "model" => Dict("name" => "heisenberg", "params" => Dict(...)),
        "algorithm" => Dict("type" => "dmrg", "options" => Dict(...))
    )
    
    # Test metadata extraction
    @testset "Core Extraction" begin
        core = TNCodebase._extract_core(config)
        
        @test core["algorithm"] == "dmrg"
        @test core["system_type"] == "spin"
        @test core["N"] == 10
    end
    
    @testset "Model Extraction" begin
        model = TNCodebase._extract_model(config)
        
        @test model["name"] == "heisenberg"
        @test model["kind"] == "prebuilt"
    end
    
    @testset "Catalog Entry" begin
        entry = TNCodebase._extract_catalog_entry(
            config, "test_run_id", "completed", "/tmp/test"
        )
        
        @test entry["run_id"] == "test_run_id"
        @test entry["status"] == "completed"
        @test haskey(entry, "core")
        @test haskey(entry, "model")
    end
end
```

### Integration Tests

```julia
@testset "End-to-End Catalog" begin
    # Run simulation
    config = create_test_config()
    run_simulation_from_config(config, base_dir="test_data")
    
    # Query it
    results = query("sim", algorithm="dmrg", base_dir="test_data")
    
    @test length(results) == 1
    @test results[1]["core"]["algorithm"] == "dmrg"
    
    # Cleanup
    rm("test_data", recursive=true)
end
```

### Testing Query Filters

```julia
@testset "Query Filtering" begin
    # Create test catalog
    test_catalog = [
        Dict("run_id" => "1", "core" => Dict("N" => 10)),
        Dict("run_id" => "2", "core" => Dict("N" => 20)),
        Dict("run_id" => "3", "core" => Dict("N" => 30))
    ]
    
    # Test exact match
    filtered = TNCodebase._filter_by_key(test_catalog, "N", 20)
    @test length(filtered) == 1
    @test filtered[1]["run_id"] == "2"
    
    # Test greater than
    filtered = TNCodebase._filter_by_key(test_catalog, "N_gt", 15)
    @test length(filtered) == 2
    
    # Test range
    filtered = TNCodebase._filter_by_key(test_catalog, "N_gte", 15)
    filtered = TNCodebase._filter_by_key(filtered, "N_lte", 25)
    @test length(filtered) == 1
    @test filtered[1]["run_id"] == "2"
end
```

---

## Debugging

### Common Issues

#### Issue 1: Catalog Entry Missing Fields

**Symptom:**
```julia
results = query("sim", algorithm="dmrg")
results[1]["algorithm_params"]["chi_max"]  # KeyError!
```

**Debug:**
```julia
# Check what's in the entry
println(results[1])

# Check extraction function
config = load_config(results[1])
params = TNCodebase._extract_algorithm_params(config)
println(params)  # Is chi_max there?
```

**Fix:** Add field to `_extract_algorithm_params()`

#### Issue 2: Query Returns Nothing

**Symptom:**
```julia
results = query("sim", model_name="heisenberg")
isempty(results)  # true, but simulations exist!
```

**Debug:**
```julia
# Load catalog directly
catalog = TNCodebase._load_catalog(base_dir="data")
println(length(catalog), " entries")

# Check first entry
println(catalog[1])

# Check model field
println(catalog[1]["model"])  # Is "name" there? Correct value?
```

**Common cause:** Typo in filter key or catalog field name

#### Issue 3: Catalog Corruption

**Symptom:**
```julia
results = query("sim", ...)  # JSON parse error
```

**Debug:**
```bash
# Find bad line
cat data/run_catalog.jsonl | while read line; do
    echo "$line" | python -m json.tool > /dev/null || echo "Bad line: $line"
done
```

**Fix:** Remove or fix corrupted line, or rebuild catalog

### Debugging Tools

**Inspect catalog directly:**
```julia
using JSON

# Load and pretty-print
catalog = JSON.parsefile("data/run_catalog.jsonl")
JSON.print(stdout, catalog[1], 2)  # Pretty print first entry
```

**Trace query execution:**
```julia
# Add debug prints to _filter_by_key
function _filter_by_key(entries, key, value)
    println("Filtering by $key = $value")
    println("  Before: $(length(entries)) entries")
    
    # ... filtering logic ...
    
    println("  After: $(length(filtered)) entries")
    return filtered
end
```

**Check catalog file integrity:**
```julia
function validate_catalog(; base_dir="data")
    catalog_path = joinpath(base_dir, "run_catalog.jsonl")
    
    line_num = 0
    errors = 0
    
    for line in eachline(catalog_path)
        line_num += 1
        try
            entry = JSON.parse(line)
            
            # Check required fields
            required = ["run_id", "status", "core", "model"]
            for field in required
                if !haskey(entry, field)
                    println("Line $line_num: Missing field $field")
                    errors += 1
                end
            end
        catch e
            println("Line $line_num: Parse error - $e")
            errors += 1
        end
    end
    
    println("Validation complete: $errors errors in $line_num entries")
end
```

---

## Best Practices

### 1. Always Extract, Never Hard-Code

**❌ Don't:**
```julia
entry["N"] = 20  # Hard-coded!
```

**✅ Do:**
```julia
entry["N"] = config["system"]["N"]  # From config
```

### 2. Handle Missing Fields Gracefully

**❌ Don't:**
```julia
params["chi_max"] = config["algorithm"]["options"]["chi_max"]  # Crashes if missing!
```

**✅ Do:**
```julia
params["chi_max"] = get(config["algorithm"]["options"], "chi_max", nothing)
```

### 3. Validate Before Appending

**✅ Do:**
```julia
function _append_to_catalog(entry, ...)
    # Validate first
    required = ["run_id", "status", "core"]
    for field in required
        if !haskey(entry, field)
            error("Missing required field: $field")
        end
    end
    
    # Then append
    open(catalog_path, "a") do f
        println(f, JSON.json(entry))
    end
end
```

### 4. Keep Extraction Functions Pure

**✅ Do:**
```julia
function _extract_model(config::Dict)
    # Pure function - no side effects
    # Only reads config, returns Dict
    return Dict("name" => config["model"]["name"])
end
```

**❌ Don't:**
```julia
function _extract_model(config::Dict)
    # Don't modify global state!
    global LAST_MODEL = config["model"]["name"]
    
    # Don't do I/O!
    open("models.txt", "a") do f
        println(f, config["model"]["name"])
    end
end
```

### 5. Document Custom Fields

```julia
"""
Extract algorithm parameters from config.

Returns Dict with following structure:
- For DMRG:
  - chi_max: Maximum bond dimension
  - n_sweeps: Number of sweeps
  - cutoff: Truncation cutoff
  - solver: Eigensolver type (added in v1.2)
  
- For my_algorithm (added in v2.0):
  - my_param1: Description
  - my_param2: Description
"""
function _extract_algorithm_params(config::Dict)
    # ...
end
```

### 6. Version Catalog Schema

```julia
# In catalog entry
entry = Dict(
    "catalog_version" => "2.0",  # Schema version
    "run_id" => ...,
    ...
)
```

Then handle old versions:
```julia
function _load_catalog(; base_dir="data")
    entries = []
    for line in eachline(catalog_path)
        entry = JSON.parse(line)
        
        # Migrate old schemas
        if !haskey(entry, "catalog_version")
            entry = _migrate_v1_to_v2(entry)
        end
        
        push!(entries, entry)
    end
    return entries
end
```

### 7. Test with Edge Cases

```julia
@testset "Edge Cases" begin
    # Empty config
    config = Dict()
    @test_throws ErrorException _extract_core(config)
    
    # Missing optional fields
    config = Dict("system" => Dict("type" => "spin", "N" => 10))
    # Should not crash!
    model = _extract_model(config)
    
    # Unusual values
    config["system"]["N"] = 0
    core = _extract_core(config)
    @test core["N"] == 0  # Should handle gracefully
end
```

---

## Summary

### Key Takeaways

✅ **Modular design** - Extraction functions, delegation pattern  
✅ **Generic system** - New algorithms/observables work automatically  
✅ **Extensible filtering** - Easy to add new query operators  
✅ **Defensive coding** - Handle missing fields gracefully  
✅ **Well-tested** - Unit and integration tests  
✅ **Debuggable** - Validation tools, clear error messages  

### Common Development Tasks

| Task | Where to Look | What to Modify |
|------|---------------|----------------|
| Add new algorithm | `database_catalog.jl` | `_extract_algorithm_params()` |
| Add new observable | Just implement calculation | Nothing! Auto-supported |
| Add query filter | `query_catalog.jl` | `_filter_by_key()` |
| Add catalog field | `database_catalog.jl` | Extraction functions |
| Fix catalog corruption | Command line | Validate and rebuild |

### Getting Help

1. **Read the code** - Functions are well-documented
2. **Check tests** - `test/test_catalog.jl` has examples
3. **Debug with prints** - Add `println()` to trace execution
4. **Validate catalog** - Use validation tools
5. **Ask questions** - File GitHub issues

---

**Congratulations!** You now understand the catalog and query system architecture and can extend it for your needs! 🎉
