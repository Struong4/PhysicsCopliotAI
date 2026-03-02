# MCP Pipeline: LLM-Driven Simulation Interface

## Overview

The MCP (Model Context Protocol) Pipeline is a chat-based interface that allows users to build, validate, and launch quantum many-body simulations through natural language conversation with an LLM. It replaces the manual process of filling HTML form fields with an intelligent assistant that understands physics vocabulary and automatically assembles valid configuration files.

The MCP server is **fully independent** of the Julia backend — it reads JSON registry files and communicates with the simulation engine exclusively through HTTP.

---

## System Architecture

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                           USER INTERACTION LAYER                             │
│                                                                              │
│   ┌──────────────┐         ┌──────────────┐                                  │
│   │   Chat UI     │         │   HTML GUI    │                                 │
│   │  (Terminal/   │         │ (config_      │                                 │
│   │   Web App)    │         │  builder.html)│                                 │
│   └──────┬───────┘         └──────┬───────┘                                  │
│          │ natural language        │ form input                               │
└──────────┼────────────────────────┼──────────────────────────────────────────┘
           │                        │
           ▼                        │
┌──────────────────────┐            │
│       LLM (Claude)   │            │
│                      │            │
│  Interprets intent,  │            │
│  calls MCP tools     │            │
└──────────┬───────────┘            │
           │ tool calls              │
           ▼                        │
┌──────────────────────┐            │
│   MCP Server         │            │
│   (Python)           │            │
│                      │            │
│  Reads registry,     │            │
│  builds configs,     │            │
│  validates,          │            │
│  submits jobs        │            │
└──────────┬───────────┘            │
           │                        │
           ▼                        ▼
     ┌─────────────────────────────────────┐
     │          JSON Config                 │    (identical format from
     │  {system, model, state, algorithm}   │     both GUI and MCP paths)
     └─────────────────┬───────────────────┘
                       │ POST /api/run
                       ▼
     ┌─────────────────────────────────────┐
     │       Julia Pipeline Server          │
     │       (pipeline_server.jl)           │
     │                                      │
     │  Dispatches to TNCodebase engine:    │
     │  - DMRG / TDVP (tensor network)     │
     │  - ED spectrum / time evolution      │
     │  - Observable calculations           │
     └─────────────────┬───────────────────┘
                       │
                       ▼
     ┌─────────────────────────────────────┐
     │        Results (data/, data_obs/)    │
     └─────────────────────────────────────┘
```

**Key point**: Both the GUI and the MCP chat path produce the **exact same JSON config**. The Julia server cannot tell which path created it.

---

## MCP Server Internal Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                        MCP Server (Python)                          │
│                                                                     │
│  ┌───────────────┐       ┌────────────────────────┐                 │
│  │ keywords.yaml │       │   registry/*.json       │                │
│  │               │       │                         │                │
│  │ STATIC        │       │ DYNAMIC                 │                │
│  │ - physics     │       │ - model names & params  │                │
│  │   vocabulary  │       │ - algorithm configs     │                │
│  │ - task→algo   │       │ - state definitions     │                │
│  │   routing     │       │ - user-registered       │                │
│  │ - interaction │       │   models & states       │                │
│  │   patterns    │       │ - system type specs     │                │
│  │ - operator    │       │                         │                │
│  │   vocabulary  │       │                         │                │
│  └───────┬───────┘       └───────────┬─────────────┘                │
│          │                           │                              │
│          ▼                           ▼                              │
│  ┌─────────────────────────────────────────────┐                    │
│  │          Runtime Indexer                      │                   │
│  │                                               │                  │
│  │  Merges static concepts + dynamic registry    │                  │
│  │  into a single searchable index.              │                  │
│  │  Rebuilds when registry files change.         │                  │
│  └──────────────────────┬────────────────────────┘                  │
│                         │                                           │
│          ┌──────────────┼──────────────┐                            │
│          ▼              ▼              ▼                             │
│  ┌──────────────┐ ┌──────────┐ ┌────────────┐ ┌──────────────┐     │
│  │  Discovery   │ │ Builder  │ │ Validator  │ │  Executor    │     │
│  │  Tools       │ │ Tools    │ │ Tool       │ │  Tools       │     │
│  │              │ │          │ │            │ │              │     │
│  │ search       │ │ build    │ │ validate   │ │ submit       │     │
│  │ get_schema   │ │ config   │ │ config     │ │ simulation   │     │
│  │ suggest_algo │ │ fill     │ │ against    │ │ check        │     │
│  │              │ │ defaults │ │ registry   │ │ status       │     │
│  └──────────────┘ └──────────┘ └────────────┘ └──────────────┘     │
│                                                      │              │
└──────────────────────────────────────────────────────┼──────────────┘
                                                       │
                                                       │ HTTP
                                                       ▼
                                              Julia Pipeline Server
```

---

## File Structure

```
mcp_bridge/
├── server.py                  # MCP entry point, tool registration
├── config.py                  # Paths to registry, Julia server URL
│
├── index/
│   ├── keywords.yaml          # Static physics vocabulary
│   └── indexer.py             # Merges keywords + registry at runtime
│
├── registry/
│   └── loader.py              # Reads & caches registry/*.json
│
├── tools/
│   ├── discovery.py           # search_registry, get_model_schema, suggest_algorithm
│   ├── builder.py             # build_config, fill_defaults
│   ├── validator.py           # validate_config
│   └── executor.py            # submit_simulation, check_status
│
└── requirements.txt           # mcp, pyyaml, httpx
```

---

## Static vs Dynamic Knowledge Split

The system separates knowledge that never changes (physics concepts) from knowledge that grows over time (available models):

```
┌─────────────────────────────────┐    ┌──────────────────────────────────┐
│      keywords.yaml (STATIC)     │    │     registry/*.json (DYNAMIC)    │
│   Ships with the tool, rarely   │    │   Grows as users register new    │
│   updated                       │    │   models and states              │
├─────────────────────────────────┤    ├──────────────────────────────────┤
│                                 │    │                                  │
│  Physics vocabulary:            │    │  models.json:                    │
│    ferromagnetic → J < 0        │    │    prebuilt_models (5 models)    │
│    antiferromagnetic → J > 0    │    │    custom_models (2 grammars)    │
│    dipolar → alpha = 3          │    │    user_models (grows)           │
│    critical → model-specific    │    │                                  │
│                                 │    │  systems.json:                   │
│  Task routing:                  │    │    spin, spinboson definitions   │
│    ground state → dmrg / ed     │    │    operator catalogs             │
│    time evolution → tdvp / ed   │    │    Hilbert space constraints     │
│    spectrum → ed only           │    │                                  │
│                                 │    │  states.json:                    │
│  System detection:              │    │    prebuilt patterns             │
│    cavity, photon → spinboson   │    │    user_states (grows)           │
│    spin chain → spin            │    │                                  │
│                                 │    │  algorithms.json:                │
│  Interaction patterns:          │    │    dmrg, tdvp, ed_spectrum,      │
│    nearest neighbor → range 1   │    │    ed_time_evolution configs     │
│    power law → long range       │    │                                  │
│    all-to-all → infinite range  │    │                                  │
│                                 │    │                                  │
│  Operator vocabulary:           │    │                                  │
│    magnetization → Z            │    │                                  │
│    transverse → X               │    │                                  │
│    raising → Sp                 │    │                                  │
│                                 │    │                                  │
│  dtype rules:                   │    │                                  │
│    Y, Sp, Sm → ComplexF64       │    │                                  │
│    X, Z, I only → Float64 ok   │    │                                  │
└─────────────────────────────────┘    └──────────────────────────────────┘
              │                                        │
              └──────────────┬─────────────────────────┘
                             │
                             ▼
                  ┌─────────────────────┐
                  │   Unified Searchable │
                  │       Index          │
                  │                      │
                  │  "heisenberg" →      │  ← learned from registry
                  │    prebuilt model    │
                  │                      │
                  │  "ferromagnetic" →   │  ← from keywords.yaml
                  │    J < 0             │
                  │                      │
                  │  "my_custom_model" → │  ← learned from registry
                  │    user model        │     (auto-discovered)
                  └─────────────────────┘
```

**Why this matters**: When a user registers "my_frustrated_chain" via the GUI, the MCP server discovers it automatically on the next search — no code changes, no keywords.yaml update.

---

## MCP Tools Reference

### Discovery Tools

| Tool | Input | Output | Purpose |
|------|-------|--------|---------|
| `search_registry` | `query: str` | Ranked matches with relevance scores | Find models/states/algorithms matching natural language |
| `get_model_schema` | `model_name: str` | Params, defaults, constraints, hamiltonian | Get full specification of a model |
| `get_algorithm_schema` | `algorithm_name: str` | Config structure, params, defaults | Get full specification of an algorithm |
| `get_state_schema` | `state_type: str` | Params, defaults, examples | Get full specification of a state pattern |
| `suggest_algorithm` | `task: str, N: int, S: float` | Algorithm name, reason, template | Recommend algorithm based on task and system size |

### Builder Tools

| Tool | Input | Output | Purpose |
|------|-------|--------|---------|
| `build_config` | `system, model, state, algorithm` | Complete JSON config | Assemble config from 4 blocks, fill defaults from registry |
| `fill_defaults` | `partial_config: dict` | Config with all defaults filled | Complete a partial config using registry defaults |

### Validation Tool

| Tool | Input | Output | Purpose |
|------|-------|--------|---------|
| `validate_config` | `config: dict` | `{valid, errors[], warnings[]}` | Check required fields, types, N limits, dtype compatibility |

### Executor Tools

| Tool | Input | Output | Purpose |
|------|-------|--------|---------|
| `submit_simulation` | `config: dict` | `{tracking_id, status}` | POST config to Julia server's `/api/run` |
| `check_status` | `tracking_id: str` | `{status, message, result?}` | GET status from `/api/status/:id` |

---

## Config Building Flow

The builder is **completely registry-driven** — it contains no hardcoded model or algorithm knowledge:

```
User says: "Run DMRG on a 20-site Heisenberg chain, Jz=2, neel state"
                                    │
                                    ▼
                         LLM extracts intent:
                           model = heisenberg
                           N = 20, Jz = 2
                           state = neel
                           algorithm = dmrg
                                    │
                                    ▼
┌───────────────────────────────────────────────────────────────────┐
│                    builder.py: build_config()                     │
│                                                                   │
│  1. Read systems.json                                             │
│     → "spin" needs: type, dtype, N, S                             │
│     → defaults: dtype=ComplexF64, S=0.5                           │
│                                                                   │
│  2. Read models.json → prebuilt_models.heisenberg                 │
│     → required_params: [Jx, Jy, Jz, hx, hy, hz]                 │
│     → defaults: {Jx:1, Jy:1, Jz:1, hx:0, hy:0, hz:0}           │
│     → user provided Jz=2, rest filled from defaults               │
│     → dtype_rule: "Jy≠0 → ComplexF64"  ✓ already ComplexF64     │
│                                                                   │
│  3. Read states.json → prebuilt.neel                              │
│     → requires: eigenstate_A, eigenstate_B                        │
│     → defaults: {eigenstate_A: 1, eigenstate_B: 2}               │
│                                                                   │
│  4. Read algorithms.json → dmrg                                   │
│     → defaults: {nsweeps:10, chi_max:128, cutoff:1e-10}          │
│     → N=20 within dmrg limits  ✓                                 │
│                                                                   │
│  5. Assemble:                                                     │
└───────────────────────┬───────────────────────────────────────────┘
                        │
                        ▼
               ┌─────────────────────────────────────────┐
               │  {                                       │
               │    "system": {                           │
               │      "type": "spin",                     │
               │      "dtype": "ComplexF64",              │
               │      "N": 20,                            │
               │      "S": 0.5                            │
               │    },                                    │
               │    "model": {                            │
               │      "name": "heisenberg",               │
               │      "params": {                         │
               │        "Jx": 1, "Jy": 1, "Jz": 2,      │
               │        "hx": 0, "hy": 0, "hz": 0        │
               │      }                                   │
               │    },                                    │
               │    "state": {                            │
               │      "type": "prebuilt",                 │
               │      "name": "neel",                     │
               │      "params": {                         │
               │        "eigenstate_A": 1,                │
               │        "eigenstate_B": 2                 │
               │      }                                   │
               │    },                                    │
               │    "algorithm": {                        │
               │      "type": "dmrg",                     │
               │      "nsweeps": 10,                      │
               │      "chi_max": 128,                     │
               │      "cutoff": 1e-10,                    │
               │      "local_dim": 2                      │
               │    }                                     │
               │  }                                       │
               └─────────────────────────────────────────┘
```

---

## Scalability: Adding New Components

The MCP server requires **zero code changes** when the registry grows:

```
┌─────────────────────────────────────────────────────────────────────┐
│                     Adding a New Model                              │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  Option A: Register via GUI                                         │
│    → GUI writes to registry/models.json (user_models section)       │
│    → MCP indexer picks it up on next search                         │
│    → Builder reads its params/defaults from registry                │
│    → No code changes anywhere                                       │
│                                                                     │
│  Option B: Add prebuilt model                                       │
│    → Developer edits registry/models.json (prebuilt_models section) │
│    → Developer edits Julia builders (modelbuilder.jl)               │
│    → MCP indexer picks it up on next search                         │
│    → No MCP code changes                                            │
│                                                                     │
├─────────────────────────────────────────────────────────────────────┤
│                     Adding a New Algorithm                          │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  → Developer adds entry to registry/algorithms.json                 │
│  → Developer implements algorithm in Julia                          │
│  → MCP indexer picks it up on next search                           │
│  → Optionally add task routing triggers to keywords.yaml            │
│  → No MCP code changes                                              │
│                                                                     │
├─────────────────────────────────────────────────────────────────────┤
│                     Adding a New System Type                        │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  → Developer adds entry to registry/systems.json                    │
│  → Developer implements in Julia                                    │
│  → MCP builder reads new fields/constraints from registry           │
│  → Optionally add detection triggers to keywords.yaml               │
│  → No MCP code changes                                              │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Conversation Flow Examples

### Example 1: Ground State Calculation

```
User: "Find the ground state energy of a 10-site antiferromagnetic
       Heisenberg chain"

Step 1 — Discovery:
  LLM calls search_registry("antiferromagnetic heisenberg ground state")
  ├── keywords.yaml: "antiferromagnetic" → J > 0
  ├── keywords.yaml: "ground state" → task=ground_state
  └── registry:      "heisenberg" → prebuilt model

Step 2 — Algorithm Selection:
  LLM calls suggest_algorithm(task="ground_state", N=10, S=0.5)
  └── N=10 ≤ 14 → ed_spectrum (exact), also viable: dmrg

Step 3 — Schema Lookup:
  LLM calls get_model_schema("heisenberg")
  └── params: {Jx, Jy, Jz, hx, hy, hz}, defaults: all 1.0/0.0

Step 4 — Config Assembly:
  LLM calls build_config(
    system    = {type: "spin", N: 10, S: 0.5},
    model     = {name: "heisenberg", params: {Jx:1, Jy:1, Jz:1}},
    algorithm = {type: "ed_spectrum"}
  )

Step 5 — Validation:
  LLM calls validate_config(config)
  └── {valid: true, warnings: []}

Step 6 — Execution:
  LLM calls submit_simulation(config)
  └── {tracking_id: "20260302_150000_ab12", status: "running"}

Step 7 — Status Check:
  LLM calls check_status("20260302_150000_ab12")
  └── {status: "completed", ground_energy: -4.258...}
```

### Example 2: Quench Dynamics (Spin-Boson)

```
User: "Simulate the dynamics of a Dicke model with 6 spins
       in a cavity, starting from all spins down and vacuum photon state,
       coupling g=0.3"

Step 1 — Discovery:
  LLM calls search_registry("dicke cavity dynamics")
  ├── keywords.yaml: "cavity" → system_type=spinboson
  ├── keywords.yaml: "dynamics" → task=time_evolution
  └── registry:      "ising_dicke" → prebuilt spinboson model

Step 2 — Algorithm Selection:
  LLM calls suggest_algorithm(task="time_evolution", N=7, S=0.5)
  └── Total sites = 6 spins + 1 boson = 7, D manageable → ed_time_evolution

Step 3 — Config Assembly:
  LLM calls build_config(
    system    = {type: "spinboson", N_spins: 6, nmax: 4, S: 0.5},
    model     = {name: "ising_dicke", params: {J: -1, h: 0.5, omega: 1, g: 0.3}},
    state     = {type: "prebuilt", name: "polarized",
                 params: {eigenstate: 1, boson_level: 0}},
    algorithm = {type: "ed_time_evolution", dt: 0.05, n_steps: 200}
  )

Step 4–6 — Validate → Submit → Monitor
```

### Example 3: User-Defined Model

```
User: "I saved a model called my_frustrated_chain last week,
       run DMRG on 50 sites with chi=256"

Step 1 — Discovery:
  LLM calls search_registry("my_frustrated_chain")
  └── registry: user_models.models.my_frustrated_chain
      (auto-discovered, no keywords.yaml entry needed)

Step 2 — Schema Lookup:
  LLM calls get_model_schema("my_frustrated_chain")
  └── {system_type: "spin", backend: "tn", channels: [...]}

Step 3 — Config Assembly:
  LLM calls build_config(
    system    = {type: "spin", N: 50, S: 0.5},
    model     = {name: "my_frustrated_chain"},  ← uses saved channels
    algorithm = {type: "dmrg", chi_max: 256}
  )

Step 4–6 — Validate → Submit → Monitor
```

---

## Independence Guarantees

```
┌─────────────────────────────────────────────────────────────────────┐
│                    DECOUPLING BOUNDARIES                            │
│                                                                     │
│  MCP Server (Python)          Julia Server                          │
│  ─────────────────────        ─────────────────                     │
│  Knows: JSON schemas          Knows: Physics, linear algebra        │
│  Reads: registry/*.json       Reads: JSON config from HTTP body     │
│  Speaks: MCP protocol         Speaks: HTTP REST API                 │
│  Depends on: Python, httpx    Depends on: Julia, TNCodebase         │
│                                                                     │
│         │                              ▲                            │
│         │    JSON config (HTTP)        │                            │
│         └──────────────────────────────┘                            │
│                                                                     │
│  If Julia is replaced:        → Only executor.py URL changes        │
│  If MCP is replaced:          → Julia server unchanged              │
│  If registry format changes:  → Only loader.py + builder.py update  │
│  If new model added:          → Zero code changes (registry-driven) │
│  If LLM provider switches:    → MCP protocol is provider-agnostic  │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Shared Components

The MCP pipeline shares these existing components with the GUI pipeline:

| Component | Location | Used by GUI | Used by MCP |
|-----------|----------|:-----------:|:-----------:|
| Registry files | `registry/*.json` | Yes (fetched via API) | Yes (read directly) |
| Julia server | `pipeline_server.jl` | Yes (POST /api/run) | Yes (POST /api/run) |
| Config format | JSON with 4 blocks | Yes (built by JS) | Yes (built by Python) |
| Data storage | `data/`, `data_obs/` | Yes | Yes |
| Catalog system | JSONL catalogs | Yes (GET /api/catalog) | Yes (GET /api/catalog) |

---

## Technology Stack

| Layer | Technology | Role |
|-------|-----------|------|
| Chat interface | Terminal / Web UI | User input |
| LLM | Claude (via MCP) | Intent extraction, conversation |
| MCP Server | Python 3.10+ | Tool serving, config assembly |
| Keyword index | YAML | Static physics vocabulary |
| Registry | JSON | Dynamic model/state/algorithm catalog |
| Simulation engine | Julia + TNCodebase | DMRG, TDVP, ED computations |
| Communication | HTTP REST | MCP server ↔ Julia server |
| Data format | JSON configs, JLD2 results | Input/output |
