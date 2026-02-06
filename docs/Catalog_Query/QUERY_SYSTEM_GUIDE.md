# QUERY SYSTEM GUIDE

## 📋 Table of Contents
1. [Overview](#overview)
2. [Unified Query API](#unified-query-api)
3. [Query Functions](#query-functions)
4. [Filter Syntax](#filter-syntax)
5. [Display Functions](#display-functions)
6. [Helper Functions](#helper-functions)
7. [HTML Query Builder](#html-query-builder)
8. [Advanced Querying](#advanced-querying)
9. [Performance Tips](#performance-tips)

---

## Overview

The **Query System** provides a unified, user-friendly interface for searching and retrieving simulation and observable data from the catalog system.

### Key Features

✅ **Unified API** - Same functions for simulations and observables  
✅ **Flexible filtering** - Query by any combination of parameters  
✅ **Type auto-detection** - Functions know what type of results they handle  
✅ **HTML query builder** - Generate queries visually in browser  
✅ **Metadata tagging** - Results tagged for reliable type detection  
✅ **Chainable operations** - Filter → display → extract → load

### Design Philosophy

**One function name, multiple query types:**
```julia
# Same function name, different contexts
query("sim", algorithm="dmrg")      # Query simulations
query("obs", observable_type="...")  # Query observables

# Same display function for both
display_results(results)
```

**User specifies type ONCE:**
```julia
# Specify "sim" or "obs" at query time
results = query("sim", ...)

# Then forget about it - all functions work!
display_results(results)      # Auto-detects simulation results
ids = get_run_ids(results)    # Auto-detects simulation results
```

---

## Unified Query API

### Core Functions

| Function | Purpose | Example |
|----------|---------|---------|
| `query(kind, ...)` | Query catalog | `query("sim", algorithm="dmrg")` |
| `display_results(results)` | Display detailed view | `display_results(results)` |
| `display_results_compact(results)` | Display table view | `display_results_compact(results)` |
| `get_run_ids(results)` | Extract run IDs | `ids = get_run_ids(results)` |
| `get_run_dirs(results)` | Extract directories | `dirs = get_run_dirs(results)` |
| `load_config(result)` | Load full config | `config = load_config(results[1])` |
| `catalog_summary(kind)` | Show catalog stats | `catalog_summary("sim")` |
| `build_query(kind)` | Open HTML builder | `build_query("sim")` |

### Type Keywords

**Simulations:**
- `"sim"` ⭐ (recommended)
- `"simulation"`
- `"run"`
- `"runs"`
- `"simulations"`

**Observables:**
- `"obs"` ⭐ (recommended)
- `"observable"`
- `"observables"`
- `"analysis"`

---

## Query Functions

### Basic Query Syntax

```julia
query(kind::String, filters...; kwargs...)
```

**Arguments:**
- `kind`: Query type ("sim" or "obs")
- `filters...`: Keyword argument filters
- `kwargs...`: Additional options (base_dir, obs_base_dir)

**Returns:**
- `Vector{Dict{String, Any}}`: Array of matching catalog entries

### Simulation Queries

#### Query by Algorithm
```julia
# All DMRG runs
results = query("sim", algorithm="dmrg")

# All ED spectrum runs
results = query("sim", algorithm="ed_spectrum")

# All TDVP runs
results = query("sim", algorithm="tdvp")
```

#### Query by Status
```julia
# Only completed runs
results = query("sim", status="completed")

# Only failed runs
results = query("sim", status="failed")
```

#### Query by Model
```julia
# All Heisenberg runs
results = query("sim", model_name="heisenberg")

# Transverse field Ising
results = query("sim", model_name="transverse_field_ising")

# With specific parameter
results = query("sim", model_name="heisenberg", model_Jz=1.0)
```

#### Query by System Size
```julia
# Exact size
results = query("sim", N=20)

# Greater than
results = query("sim", N_gt=10)

# Greater than or equal
results = query("sim", N_gte=20)

# Less than
results = query("sim", N_lt=100)

# Less than or equal
results = query("sim", N_lte=50)

# Range (combine)
results = query("sim", N_gte=20, N_lte=50)
```

#### Query by State
```julia
# By state kind
results = query("sim", state_kind="prebuilt")

# By state name
results = query("sim", state_name="neel")

# By state parameter
results = query("sim", state_name="polarized", state_spin_direction="Z")
```

#### Query by Algorithm Parameters
```julia
# Prefix with "algo_"
results = query("sim", algorithm="dmrg", algo_chi_max=100)

results = query("sim", algorithm="tdvp", algo_dt=0.01)

# With comparison operators
results = query("sim", algorithm="dmrg", algo_chi_max_gte=50)
```

#### Combining Filters
```julia
# Complex query
results = query("sim",
    status="completed",
    algorithm="dmrg",
    model_name="heisenberg",
    N_gte=20,
    algo_chi_max_gte=100
)
```

#### Custom Base Directory
```julia
results = query("sim", algorithm="dmrg", base_dir="custom_data")
```

### Observable Queries

#### Query by Observable Type
```julia
# Entanglement entropy
results = query("obs", observable_type="entanglement_entropy")

# Correlation functions
results = query("obs", observable_type="correlation_function")

# Magnetization
results = query("obs", observable_type="magnetization")
```

#### Query by Observable Parameters
```julia
# Prefix with "observable_"
results = query("obs",
    observable_type="entanglement_entropy",
    observable_bond=5
)

results = query("obs",
    observable_type="correlation_function",
    observable_operator="Z"
)
```

#### Query by Simulation Properties
```julia
# By simulation algorithm (prefix with "sim_")
results = query("obs", sim_algorithm="dmrg")

# By simulation model
results = query("obs", sim_model_name="heisenberg")

# Combine
results = query("obs",
    sim_algorithm="ed_spectrum",
    sim_model_name="transverse_field_ising"
)
```

#### Query by Analysis Parameters
```julia
# By selection type
results = query("obs", analysis_selection_type="all")

results = query("obs", analysis_selection_type="specific")
```

#### Complex Observable Query
```julia
results = query("obs",
    observable_type="entanglement_entropy",
    observable_bond=10,
    sim_algorithm="dmrg",
    sim_model_name="heisenberg",
    analysis_selection_type="last"
)
```

#### Custom Observable Directory
```julia
results = query("obs", 
    observable_type="entanglement_entropy",
    base_dir="custom_observables"
)
```

---

## Filter Syntax

### Filter Keys

**Simulation filters:**

| Category | Filters | Example |
|----------|---------|---------|
| **Status** | `status` | `status="completed"` |
| **Algorithm** | `algorithm` | `algorithm="dmrg"` |
| **System** | `system_type`, `N`, `S`, `dtype` | `system_type="spin"` |
| **Model** | `model_name`, `model_*` | `model_name="heisenberg"` |
| **State** | `state_kind`, `state_name`, `state_*` | `state_kind="prebuilt"` |
| **Algo params** | `algo_*` | `algo_chi_max=100` |
| **Results** | `result_*` | `result_ground_energy_lt=-8.0` |

**Observable filters:**

| Category | Filters | Example |
|----------|---------|---------|
| **Observable** | `observable_type`, `observable_*` | `observable_type="entanglement"` |
| **Simulation** | `sim_algorithm`, `sim_model_name`, `sim_*` | `sim_algorithm="dmrg"` |
| **Analysis** | `analysis_*` | `analysis_selection_type="all"` |

### Comparison Operators

For numeric fields, append operator suffix:

| Operator | Suffix | Example | Meaning |
|----------|--------|---------|---------|
| `=` | (none) | `N=20` | Exact match |
| `>` | `_gt` | `N_gt=10` | Greater than |
| `>=` | `_gte` | `N_gte=10` | Greater than or equal |
| `<` | `_lt` | `N_lt=100` | Less than |
| `<=` | `_lte` | `N_lte=100` | Less than or equal |

**Examples:**
```julia
# N > 10
query("sim", N_gt=10)

# N >= 20
query("sim", N_gte=20)

# N < 100
query("sim", N_lt=100)

# 20 <= N <= 50
query("sim", N_gte=20, N_lte=50)

# chi_max >= 100
query("sim", algo_chi_max_gte=100)

# Ground energy < -8.0
query("sim", result_ground_energy_lt=-8.0)
```

### Nested Field Access

**Access nested parameters with prefixes:**

```julia
# Model parameters: model_*
query("sim", model_Jx=1.0, model_Jy=1.0, model_Jz=1.0)

# State parameters: state_*
query("sim", state_bond_dim=10)

# Algorithm parameters: algo_*
query("sim", algo_chi_max=100, algo_cutoff=1e-8)

# Observable parameters: observable_*
query("obs", observable_bond=5, observable_operator="Z")

# Simulation reference in observables: sim_*
query("obs", sim_algorithm="dmrg", sim_model_name="heisenberg")
```

---

## Display Functions

### Detailed Display

```julia
display_results(results::Vector{Dict})
```

**Output format:**
```
────────────────────────────────────────────────────────────────────
Run: 20260201_143022_a4f3b891
────────────────────────────────────────────────────────────────────
  Status: completed
  Algorithm: dmrg
  System: spin (N=20, S=0.5)
  Model: heisenberg (Jx=1.0, Jy=1.0, Jz=1.0)
  State: neel
  Results: ground_energy=-8.724, bond_dim=45
  Path: data/dmrg/20260201_143022_a4f3b891

────────────────────────────────────────────────────────────────────
Run: 20260201_151533_b7e9c123
────────────────────────────────────────────────────────────────────
...
```

**Works for both:**
```julia
sim_results = query("sim", algorithm="dmrg")
display_results(sim_results)  # Shows simulation details

obs_results = query("obs", observable_type="entanglement")
display_results(obs_results)  # Shows observable details
```

### Compact Display (Table)

```julia
display_results_compact(results::Vector{Dict})
```

**Output format:**
```
────────────────────────────────────────────────────────────────────
run_id                       status     algo     N      model       state    
────────────────────────────────────────────────────────────────────
20260201_143022_a4f3b891     completed  dmrg     20     heisenberg  neel     
20260201_151533_b7e9c123     completed  dmrg     20     heisenberg  neel     
20260201_154411_c8d4e567     completed  dmrg     20     heisenberg  neel     
────────────────────────────────────────────────────────────────────
Total: 3 run(s)
```

**Great for:**
- Quick overview of many results
- Comparing multiple runs
- Finding specific run_id

---

## Helper Functions

### Extract Run IDs

```julia
get_run_ids(results::Vector{Dict}) -> Vector{String}
```

**Example:**
```julia
results = query("sim", algorithm="dmrg")
ids = get_run_ids(results)
# → ["20260201_143022_a4f3b891", "20260201_151533_b7e9c123", ...]
```

**Works for both:**
```julia
sim_ids = get_run_ids(sim_results)     # Simulation IDs
obs_ids = get_run_ids(obs_results)     # Observable IDs
```

### Extract Run Directories

```julia
get_run_dirs(results::Vector{Dict}) -> Vector{String}
```

**Example:**
```julia
results = query("sim", algorithm="dmrg")
dirs = get_run_dirs(results)
# → ["data/dmrg/20260201_143022_a4f3b891", ...]
```

**Use case:**
```julia
# Load data files directly
using JLD2
dirs = get_run_dirs(results)
data = load(joinpath(dirs[1], "results.jld2"))
```

### Load Configuration

```julia
load_config(result::Dict) -> Dict
```

**Example:**
```julia
results = query("sim", algorithm="dmrg")
config = load_config(results[1])

# Now you have the full config
println(config["algorithm"]["options"]["chi_max"])
```

**Works for both:**
```julia
sim_config = load_config(sim_results[1])   # Simulation config
obs_config = load_config(obs_results[1])   # Observable config (includes sim ref!)
```

### Catalog Summary

```julia
catalog_summary(kind::String; base_dir="data", obs_base_dir="observables")
```

**Example:**
```julia
# Simulation catalog stats
catalog_summary("sim")

# Observable catalog stats
catalog_summary("obs")
```

**Output:**
```
════════════════════════════════════════════════════════════════
Simulation Catalog Summary
════════════════════════════════════════════════════════════════

Total runs: 47

By Algorithm:
  dmrg        : 23 runs
  ed_spectrum : 12 runs
  tdvp        : 8 runs

By Status:
  completed   : 42 runs
  failed      : 5 runs

By Model:
  heisenberg : 18 runs
  tfim       : 15 runs
...
```

---

## HTML Query Builder

### Opening the Builder

```julia
build_query(kind::String; base_dir=nothing)
open_query(kind::String; base_dir=nothing)  # Alias
```

**Examples:**
```julia
# Simulation query builder
build_query("sim")
build_query()  # Default is "sim"

# Observable query builder
build_query("obs")

# Custom directory
build_query("sim", base_dir="custom_data")
```

### Using the Builder

**Workflow:**
```
1. Run build_query("sim") in Julia
   ↓
2. Browser opens with interactive form
   ↓
3. Select filters using dropdowns
   ↓
4. Generated command updates live at bottom
   ↓
5. Click "📋 Copy Command"
   ↓
6. Paste in Julia REPL and run
```

**Example session:**
```julia
julia> build_query("sim")
╔═══════════════════════════════════════════════════════╗
║   Opening SIMULATION Query Builder                   ║
╚═══════════════════════════════════════════════════════╝
  Catalog: data/run_catalog.jsonl

✓ Opened query builder with 47 catalog entries
```

**Browser shows:**
- Filter dropdowns populated from catalog
- Live command preview
- Copy button
- Help documentation

**Select in browser:**
- Algorithm: dmrg
- Model: heisenberg
- N: >= 20

**Generated command:**
```julia
results = query("sim", algorithm="dmrg", model_name="heisenberg", N_gte=20)
```

**Copy and run:**
```julia
julia> results = query("sim", algorithm="dmrg", model_name="heisenberg", N_gte=20)
3-element Vector{Dict{String, Any}}

julia> display_results(results)
...
```

---

## Advanced Querying

### Chaining Operations

```julia
# Query → Filter → Display → Extract → Load
results = query("sim", algorithm="dmrg")              # 1. Query
results = filter(r -> r["core"]["N"] > 20, results)   # 2. Post-filter
display_results_compact(results)                       # 3. Display
ids = get_run_ids(results)                            # 4. Extract
config = load_config(results[1])                      # 5. Load
```

### Filtering Results

```julia
# Query gives too many results?
results = query("sim", algorithm="dmrg")

# Post-filter in Julia
large_systems = filter(r -> r["core"]["N"] > 50, results)
converged = filter(r -> r["results_summary"]["sweeps_completed"] == 50, results)
```

### Cross-Referencing

```julia
# Find all observables for a simulation
sim_results = query("sim", algorithm="ed_spectrum", model_name="heisenberg")
sim_id = get_run_ids(sim_results)[1]

# Use helper function
obs_results = get_observables_for_simulation(sim_id)
display_results(obs_results)
```

### Programmatic Queries

```julia
# Build filters programmatically
models = ["heisenberg", "transverse_field_ising", "xxz"]
all_results = []

for model in models
    results = query("sim", model_name=model, N=20)
    append!(all_results, results)
end

display_results_compact(all_results)
```

### Saving Query Results

```julia
# Save query results for later
results = query("sim", algorithm="dmrg", N_gte=50)

using JSON
open("my_query_results.json", "w") do f
    JSON.print(f, results, 2)
end

# Load later
results_loaded = JSON.parsefile("my_query_results.json")
```

---

## Performance Tips

### Query Performance

**Fast queries (< 100 ms):**
```julia
# Catalog already loaded, just filtering
query("sim", algorithm="dmrg")
query("sim", model_name="heisenberg")
```

**Slower queries (if catalog huge):**
```julia
# First query loads catalog (~50-500 ms for large catalogs)
query("sim", ...)  # Loads catalog

# Subsequent queries are fast (catalog cached)
query("sim", ...)  # Uses cached catalog
```

**Optimization:**
```julia
# If doing many queries, load catalog once
catalog = _load_catalog(base_dir="data")

# Then filter manually (advanced)
dmrg_runs = filter(e -> e["core"]["algorithm"] == "dmrg", catalog)
```

### Result Set Size

**Small result sets (< 100):**
```julia
# Fast to display, extract, process
results = query("sim", algorithm="dmrg", model_name="heisenberg")
display_results(results)  # Quick
```

**Large result sets (> 1000):**
```julia
# Use compact display
results = query("sim", status="completed")  # Many results
display_results_compact(results)  # Table format, faster

# Or paginate
display_results(results[1:10])  # First 10
display_results(results[11:20]) # Next 10
```

### Directory Access

**Accessing actual data files:**
```julia
# Get directories
results = query("sim", algorithm="dmrg")
dirs = get_run_dirs(results)

# Load data (this is the slow part - I/O bound)
using JLD2
data = load(joinpath(dirs[1], "sweep_050.jld2"))
```

**Tip:** Only load data you actually need!

---

## Query System Architecture

### How Auto-Detection Works

**Metadata tagging:**
```julia
# query() tags results
function query(kind, ...)
    if kind in _SIM_KEYS
        results = query_catalog(...)
        for r in results
            r["_query_type"] = "simulation"  # ← Tag!
        end
    elseif kind in _OBS_KEYS
        results = query_observables(...)
        for r in results
            r["_query_type"] = "observable"  # ← Tag!
        end
    end
    return results
end

# display_results() checks tag
function display_results(results)
    if results[1]["_query_type"] == "simulation"
        return _display_simulation_results(results)
    else
        return _display_observable_results(results)
    end
end
```

**Why tagging?**
- ✅ Explicit (not implicit schema detection)
- ✅ Robust (works even if schemas change)
- ✅ Fast (just check one field)
- ✅ Reliable (no ambiguity)

### Backend Functions

**Simulation queries call:**
```julia
query("sim", ...) → query_catalog(...) → filter catalog entries
```

**Observable queries call:**
```julia
query("obs", ...) → query_observables(...) → filter observable catalog
```

**Unified wrappers delegate to specialized backends:**
```julia
query() → query_catalog() or query_observables()
display_results() → _display_simulation_results() or _display_observable_results()
get_run_ids() → simulation or observable ID extraction
```

---

## Common Patterns

### Finding Ground States

```julia
# All completed DMRG ground states
results = query("sim", algorithm="dmrg", status="completed")

# For specific model
results = query("sim", algorithm="dmrg", model_name="heisenberg")

# Large systems only
results = query("sim", algorithm="dmrg", N_gte=50)
```

### Finding Eigenstates

```julia
# All ED spectrum calculations
results = query("sim", algorithm="ed_spectrum")

# For specific model and size
results = query("sim", 
    algorithm="ed_spectrum",
    model_name="transverse_field_ising",
    N=10
)
```

### Finding Time Evolution

```julia
# All time evolution runs
results = query("sim", algorithm="ed_time_evolution")

# With specific initial state
results = query("sim",
    algorithm="ed_time_evolution",
    state_name="polarized"
)
```

### Finding Observables

```julia
# All entanglement calculations
results = query("obs", observable_type="entanglement_entropy")

# For DMRG runs only
results = query("obs",
    observable_type="entanglement_entropy",
    sim_algorithm="dmrg"
)

# At specific bond
results = query("obs",
    observable_type="entanglement_entropy",
    observable_bond=10
)
```

### Comparing Algorithms

```julia
# Same model, different algorithms
model = "heisenberg"
N = 20

dmrg_results = query("sim", algorithm="dmrg", model_name=model, N=N)
ed_results = query("sim", algorithm="ed_spectrum", model_name=model, N=N)

# Compare ground energies
dmrg_energy = dmrg_results[1]["results_summary"]["ground_energy"]
ed_energy = ed_results[1]["results_summary"]["ground_state_energy"]

println("DMRG: $dmrg_energy")
println("ED:   $ed_energy")
println("Difference: $(abs(dmrg_energy - ed_energy))")
```

---

## Error Handling

### Empty Results

```julia
results = query("sim", algorithm="does_not_exist")

if isempty(results)
    println("No results found!")
else
    display_results(results)
end
```

### Invalid Filters

```julia
# Typo in filter name - silently ignored!
results = query("sim", algoritm="dmrg")  # Typo: "algoritm"
# Returns all simulations (filter ignored)

# Use catalog_summary() to see valid values
catalog_summary("sim")  # Shows available algorithms
```

### Type Detection Failure

```julia
# If results don't have _query_type tag
results = [{...}]  # Manually created, no tag

# Functions will try schema detection as fallback
display_results(results)  # May fail or detect wrong type
```

**Solution:** Always use `query()` function!

---

## Summary

The query system provides:

✅ **Unified API** - One function name for all query types  
✅ **Flexible filtering** - Any combination of parameters  
✅ **Auto-detection** - Functions know result types  
✅ **HTML builder** - Visual query construction  
✅ **Performance** - Fast catalog scanning  
✅ **Chainable** - Query → display → extract → load  
✅ **Type-safe** - Metadata tagging for reliability

**Next:** See CATALOG_QUERY_INTEGRATION.md for complete workflows!
