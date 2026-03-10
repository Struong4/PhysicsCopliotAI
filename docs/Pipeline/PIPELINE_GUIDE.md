# TNSoftware Integrated Pipeline Guide

## Overview

TNSoftware provides a three-operation pipeline for quantum many-body simulations:

```
Simulate → Query → Calculate Observable
```

Each operation is independently callable via:
- **Julia REPL** — direct function calls
- **REST API** — HTTP endpoints served by `pipeline_server.jl`
- **GUI** — browser interface at `http://localhost:8080`
- **MCP/LLM** — any tool that can make HTTP requests

The backend (Julia) is completely independent of the interface layer. All GUI, MCP, and REST interactions go through the registry and catalog system — no interface-specific logic touches the simulation or observable code.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                     Interface Layer                              │
│  ┌──────────┐  ┌──────────────┐  ┌──────────┐  ┌────────────┐  │
│  │   GUI    │  │  REST API    │  │   MCP    │  │ Julia REPL │  │
│  │ (HTML/JS)│  │(pipeline_    │  │ (LLM    │  │  (direct   │  │
│  │          │  │ server.jl)   │  │  tools) │  │  calls)    │  │
│  └────┬─────┘  └──────┬───────┘  └────┬─────┘  └─────┬──────┘  │
│       │               │               │              │          │
│       └───────┬───────┘───────┬───────┘──────┬───────┘          │
│               ▼               ▼              ▼                  │
│  ┌─────────────────────────────────────────────────────┐        │
│  │              Registry (JSON files)                  │        │
│  │  models.json  systems.json  states.json             │        │
│  │  algorithms.json  observables.json  config_schema   │        │
│  └─────────────────────────────────────────────────────┘        │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                     Backend Layer (Julia)                        │
│  ┌───────────────┐  ┌───────────────┐  ┌─────────────────────┐  │
│  │  Simulation   │  │    Query      │  │  Observable Calc    │  │
│  │  Runner       │  │   Engine      │  │    Runner           │  │
│  │               │  │               │  │                     │  │
│  │ run_simulation│  │ query_catalog │  │ run_observable_     │  │
│  │ _from_config()│  │ query_        │  │ from_run_id()       │  │
│  │               │  │ observables() │  │ run_observable_     │  │
│  │               │  │               │  │ calculation_from_   │  │
│  │               │  │               │  │ config()            │  │
│  └──────┬────────┘  └──────┬────────┘  └──────┬──────────────┘  │
│         │                  │                   │                 │
│         ▼                  ▼                   ▼                 │
│  ┌─────────────────────────────────────────────────────┐        │
│  │                 Data Layer                          │        │
│  │  data/                     data_obs/               │        │
│  │  ├── run_catalog.jsonl     ├── observables_catalog │        │
│  │  └── {algo}/{run_id}/      └── {algo}/{sim_id}/    │        │
│  │      ├── config.json           └── {obs_id}/       │        │
│  │      ├── metadata.json             ├── obs_config  │        │
│  │      └── sweep_*.jld2              ├── metadata    │        │
│  │                                    └── obs_*.jld2  │        │
│  └─────────────────────────────────────────────────────┘        │
└─────────────────────────────────────────────────────────────────┘
```

---

## Operation 1: Simulate

Run a new simulation from a JSON config. The runner automatically deduplicates: same config produces the same hash, same hash returns the existing run without recomputation.

### Julia REPL

```julia
config = JSON.parsefile("my_simulation.json")
result, run_id, run_dir = run_simulation_from_config(config; base_dir="data")
```

### REST API

```http
POST /api/run
Content-Type: application/json

{
  "mode": "simulation",
  "config": {
    "system": { "type": "spin", "N": 20, "S": 0.5, "dtype": "Float64" },
    "model": { "type": "heisenberg", "params": { "J": 1.0 } },
    "state": { "type": "random", "params": { "bond_dim": 10 } },
    "algorithm": { "type": "dmrg", "solver": { "type": "lanczos", "krylov_dim": 10 },
                   "options": { "chi_max": 128, "cutoff": 1e-10 },
                   "run": { "n_sweeps": 20 } }
  }
}
```

Response (202 Accepted):
```json
{
  "status": "accepted",
  "tracking_id": "20260309_143015_1234",
  "message": "Pipeline started in background"
}
```

Poll status:
```http
GET /api/status/20260309_143015_1234
```

### GUI

1. Select "New Simulation" mode
2. Configure system, model, state, algorithm
3. Click "Run Pipeline"

---

## Operation 2: Query

Search the catalog for existing simulation or observable runs. The query engine supports prefix-based filter routing and comparison operators.

### Julia REPL

```julia
# Simulation queries
results = query_catalog(algorithm="dmrg", N_gte=10, model_name="heisenberg")
display_results(results)

# Or use the unified interface
results = query("sim", algorithm="dmrg")
results = query("obs", observable_type="entanglement_entropy")
```

### REST API — Query Simulations

```http
GET /api/query/simulations?algorithm=dmrg&N_gte=10&model_name=heisenberg
```

Response:
```json
{
  "count": 3,
  "results": [
    {
      "run_id": "20260308_120000_a1b2c3d4",
      "status": "completed",
      "core": { "algorithm": "dmrg", "N": 20, ... },
      "model": { "name": "heisenberg", ... },
      "run_dir": "/path/to/data/dmrg/20260308_120000_a1b2c3d4"
    }
  ]
}
```

### REST API — Query Observables

```http
GET /api/query/observables?observable_type=correlation_function&sim_algorithm=dmrg
```

### Filter Syntax

**Simulation filters** (`/api/query/simulations`):
| Prefix | Targets | Examples |
|--------|---------|----------|
| (none) | Core fields | `algorithm`, `system_type`, `N`, `S`, `dtype`, `status`, `run_id` |
| `algo_` | Algorithm params | `algo_chi_max`, `algo_n_sweeps`, `algo_dt` |
| `model_` | Model fields | `model_name`, `model_kind`, `model_J` |
| `state_` | State fields | `state_kind`, `state_name`, `state_bond_dim` |
| `result_` | Result fields | `result_final_energy` |

**Observable filters** (`/api/query/observables`):
| Prefix | Targets | Examples |
|--------|---------|----------|
| (none) | Top-level | `obs_run_id`, `sim_run_id`, `status` |
| `sim_` | Simulation info | `sim_algorithm`, `sim_N`, `sim_model_name` |
| `observable_` | Observable | `observable_type`, `observable_operator` |
| `result_` | Results summary | `result_items_processed` |

**Comparison operators** — append to any field name:
- `_gt` — greater than
- `_gte` — greater than or equal
- `_lt` — less than
- `_lte` — less than or equal

Example: `N_gte=10&algo_chi_max_lt=256`

### GUI

1. Select "Query & Calculate" mode
2. Use the search filters (algorithm, system type, model, N, status)
3. Click "Search Catalog"
4. Select a simulation run from results

---

## Operation 3: Calculate Observable

Calculate observables on existing simulation data. Callers provide a `run_id` (from query) and an observable specification. The simulation config (needed for rebuilding the Hamiltonian, system params, etc.) is loaded automatically from the saved run directory — no need to pass it in.

**Julia REPL:**
```julia
obs_run_id, obs_run_dir = run_observable_from_run_id(
    "20260308_120000_a1b2c3d4",
    Dict("type" => "correlation_function",
         "params" => Dict("site_i" => 1, "site_j" => 10, "operator" => "Z")),
    Dict("selection" => "all");
    base_dir="data",
    obs_base_dir="data_obs"
)
```

**REST API:**
```http
POST /api/observables/calculate
Content-Type: application/json

{
  "run_id": "20260308_120000_a1b2c3d4",
  "observable": {
    "type": "correlation_function",
    "params": { "site_i": 1, "site_j": 10, "operator": "Z" }
  },
  "selection": { "type": "all" }
}
```

Response (202 Accepted):
```json
{
  "status": "accepted",
  "tracking_id": "20260309_143100_obs_5678",
  "message": "Observable calculation started in background"
}
```

### GUI

1. In "Query & Calculate" mode, after selecting a simulation run:
2. Configure the selection (all / range / specific / time_range)
3. Select observable type and fill parameters
4. Click "Calculate Observable"
5. View results in the results panel

---

## Retrieving Results

### Simulation Results

```http
GET /api/results/simulations/20260308_120000_a1b2c3d4
```

Returns catalog entry, config.json, and metadata.json for the run.

### Observable Results

```http
GET /api/results/observables/20260309_143100_obs_f4b2c3d1
```

Returns computed values as JSON:
```json
{
  "obs_run_id": "...",
  "catalog_entry": { ... },
  "metadata": { ... },
  "data": {
    "indices": [1, 2, 3, ...],
    "values": [0.123, 0.456, ...],
    "times": [0.0, 0.1, 0.2, ...]
  }
}
```

Values are JSON-safe: matrices become nested arrays, complex numbers become `{"real": ..., "imag": ...}`.

---

## Registry System

JSON files in `registry/` define what is available. The GUI and MCP read these to dynamically build selection interfaces.

| Registry | File | Purpose |
|----------|------|---------|
| Models | `models.json` | Prebuilt + user-defined Hamiltonians |
| Systems | `systems.json` | Spin, spin-boson systems; operators |
| States | `states.json` | Initial state types and parameters |
| Algorithms | `algorithms.json` | DMRG, TDVP, ED algorithms and params |
| Observables | `observables.json` | All 20 observables with param schemas |
| Config Schema | `config_schema.json` | Assembly rules for building configs |

### Registry REST endpoints

```http
GET  /api/registry/models          # Get models registry
GET  /api/registry/systems         # Get systems registry
GET  /api/registry/states          # Get states registry
GET  /api/registry/algorithms      # Get algorithms registry
GET  /api/registry/observables     # Get observables registry
GET  /api/registry/config_schema   # Get assembly rules

POST /api/registry/models          # Register user model
POST /api/registry/states          # Register user state
DELETE /api/registry/models/:name  # Delete user model
DELETE /api/registry/states/:name  # Delete user state
```

---

## Complete API Reference

| Method | Endpoint | Description |
|--------|----------|-------------|
| `POST` | `/api/run` | Run simulation pipeline |
| `GET` | `/api/status/:id` | Check pipeline tracking status |
| `GET` | `/api/catalog` | List all simulation runs (raw catalog) |
| `GET` | `/api/active` | List currently running pipelines |
| `GET` | `/api/query/simulations?...` | Query simulation catalog with filters |
| `GET` | `/api/query/observables?...` | Query observable catalog with filters |
| `GET` | `/api/results/simulations/:run_id` | Get simulation metadata & config |
| `GET` | `/api/results/observables/:obs_run_id` | Get observable results as JSON |
| `POST` | `/api/observables/calculate` | Calculate observable on existing data |
| `GET` | `/api/registry/:name` | Get a registry file |
| `POST` | `/api/registry/models` | Register user model |
| `POST` | `/api/registry/states` | Register user state |
| `DELETE` | `/api/registry/models/:name` | Delete user model |
| `DELETE` | `/api/registry/states/:name` | Delete user state |
| `GET` | `/` | Web GUI |
| `GET` | `/pipeline_automation.js` | JavaScript client |

---

## Starting the Server

```bash
julia start_server.jl
```

This loads the TNCodebase module and starts the HTTP server on `http://localhost:8080`.

Configuration defaults:
- Simulation data: `data/`
- Observable data: `data_obs/`
- Frontend: `frontend/`
- Registry: `registry/`

---

## GUI Modes

The web interface (`http://localhost:8080`) has three modes:

1. **New Simulation** — Build config and run a new simulation
2. **Query & Calculate** — Search for existing runs, then calculate observables
3. **Registry** — Manage saved user models and states

---

## Example: Full Pipeline via REST

```bash
# 1. Run a DMRG simulation
curl -X POST http://localhost:8080/api/run \
  -H "Content-Type: application/json" \
  -d '{"mode":"simulation","config":{"system":{"type":"spin","N":20,"S":0.5,"dtype":"Float64"},"model":{"type":"heisenberg","params":{"J":1.0}},"state":{"type":"random","params":{"bond_dim":10}},"algorithm":{"type":"dmrg","solver":{"type":"lanczos","krylov_dim":10},"options":{"chi_max":128,"cutoff":1e-10,"local_dim":2},"run":{"n_sweeps":20}}}}'

# 2. Check status
curl http://localhost:8080/api/status/TRACKING_ID

# 3. Query for the completed run
curl "http://localhost:8080/api/query/simulations?algorithm=dmrg&model_name=heisenberg&status=completed"

# 4. Calculate correlation function on the run
curl -X POST http://localhost:8080/api/observables/calculate \
  -H "Content-Type: application/json" \
  -d '{"run_id":"RUN_ID_FROM_STEP_3","observable":{"type":"correlation_function","params":{"site_i":1,"site_j":10,"operator":"Z"}},"selection":{"type":"all"}}'

# 5. Get the results
curl http://localhost:8080/api/results/observables/OBS_RUN_ID_FROM_STEP_4
```

---

## Supported Observables

| Observable | Type Key | Backends | Parameters |
|-----------|----------|----------|------------|
| Single site expectation | `single_site_expectation` | TN, ED | `site`, `operator` |
| Subsystem sum | `subsystem_expectation_sum` | TN, ED | `operator`, `l`, `m` |
| Two-site expectation | `two_site_expectation` | TN, ED | `site_i`, `site_j`, `operator_i`, `operator_j` |
| Correlation function | `correlation_function` | TN, ED | `site_i`, `site_j`, `operator` |
| Connected correlation | `connected_correlation` | TN, ED | `site_i`, `site_j`, `operator` |
| Entanglement entropy | `entanglement_entropy` | TN, ED | `bond`/`cut`, `alpha` (optional) |
| Entanglement spectrum | `entanglement_spectrum` | TN, ED | `bond`/`cut`, `n_values` (optional) |
| Energy expectation | `energy_expectation` | TN, ED | (none — uses Hamiltonian) |
| Energy variance | `energy_variance` | TN, ED | (none — uses Hamiltonian) |
| Expectation all sites | `expectation_all_sites` | ED | `operator` |
| Correlation matrix | `correlation_matrix` | ED | `operator` |
| Boson number | `boson_number` | ED (spinboson) | (none) |
| Boson distribution | `boson_distribution` | ED (spinboson) | (none) |
| Boson field | `boson_field` | ED (spinboson) | (none) |
| Boson-spin entanglement | `boson_spin_entanglement` | ED (spinboson) | `alpha` (optional) |

Operators: `Z`/`Sz`, `X`/`Sx`, `Y`/`Sy`, `Sp`/`+`, `Sm`/`-`

---

## File Organization

```
TNSoftware/
├── src/
│   ├── Runners/
│   │   ├── run_Simulation.jl        # Simulation entry point
│   │   └── run_Observable.jl        # Observable calculation (both config and run_id based)
│   ├── Database/
│   │   ├── query_catalog.jl         # Simulation catalog query engine
│   │   ├── query_observables_catalog.jl  # Observable catalog query engine
│   │   ├── query_builder.jl         # Unified query("sim"/"obs") dispatcher
│   │   ├── database_utils.jl        # Simulation data management
│   │   ├── database_catalog.jl      # Catalog append/load
│   │   ├── database_observables_utils.jl   # Observable data save/load
│   │   └── database_observables_catalog.jl # Observable catalog management
│   ├── Analysis/                    # TN observable implementations
│   ├── ED/                          # ED observable implementations
│   └── ...
├── server/
│   └── pipeline_server.jl           # REST API server (all endpoints)
├── frontend/
│   ├── config_builder.html          # Web GUI (4 modes)
│   └── pipeline_automation.js       # JS client for REST API
├── registry/
│   ├── models.json                  # Model registry
│   ├── systems.json                 # System registry
│   ├── states.json                  # State registry
│   ├── algorithms.json              # Algorithm registry
│   ├── observables.json             # Observable registry
│   └── config_schema.json           # Assembly rules
├── data/                            # Simulation output
│   ├── run_catalog.jsonl
│   └── {algorithm}/{run_id}/
├── data_obs/                        # Observable output
│   ├── observables_catalog.jsonl
│   └── {algorithm}/{sim_run_id}/{obs_run_id}/
├── start_server.jl                  # Server bootstrap
└── docs/Pipeline/PIPELINE_GUIDE.md  # This file
```
