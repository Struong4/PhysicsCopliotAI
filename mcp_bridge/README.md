# MCP Bridge — Implementation Guide

## What This Is

The MCP (Model Context Protocol) bridge enables LLM-driven quantum simulation via natural language. A user chats with an LLM, the LLM calls MCP tools, and those tools read from a physics registry to build, validate, and execute simulation configs — the same JSON configs that the existing HTML GUI produces.

This README is written for the CS collaborator. It covers:
1. What has been built (Nishan's deliverables)
2. What you need to build (MCP server plumbing)
3. How the pieces connect
4. Interface contracts between our code

---

## Big Picture Architecture

```
┌───────────────────────────────────────────────────────────────────────┐
│                        USER INTERACTION LAYER                         │
│                                                                       │
│   ┌──────────────┐              ┌──────────────┐                      │
│   │   Chat UI     │              │   HTML GUI    │                     │
│   │  (Terminal /   │              │ (config_      │                     │
│   │   Web App)     │              │  builder.html)│                     │
│   └──────┬────────┘              └──────┬───────┘                      │
│          │ natural language              │ form input                   │
└──────────┼──────────────────────────────┼─────────────────────────────┘
           │                              │
           ▼                              │
┌──────────────────────┐                  │
│     LLM (Claude)     │                  │
│                      │                  │
│  Interprets intent,  │                  │
│  calls MCP tools     │                  │
└──────────┬───────────┘                  │
           │ tool calls                    │
           ▼                              │
┌──────────────────────┐                  │
│   MCP Server         │                  │
│   (Python)           │                  │
│                      │                  │
│  Reads registry,     │                  │
│  builds configs,     │                  │
│  validates,          │                  │
│  submits jobs        │                  │
└──────────┬───────────┘                  │
           │                              │
           ▼                              ▼
     ┌─────────────────────────────────────────┐
     │          JSON Config                     │   ← identical format
     │  {system, model, state, algorithm}       │     from both paths
     └─────────────────┬───────────────────────┘
                       │ POST /api/run
                       ▼
     ┌─────────────────────────────────────────┐
     │       Julia Pipeline Server              │
     │       (pipeline_server.jl)               │
     │                                          │
     │  DMRG / TDVP / ED spectrum / ED evol    │
     └─────────────────────────────────────────┘
```

Both the GUI and the MCP chat path produce the **exact same JSON config**. The Julia server cannot tell which path created it.

---

## MCP Server Internal Architecture

```
┌──────────────────────────────────────────────────────────────────────┐
│                      MCP Server (Python)                              │
│                                                                      │
│  ┌────────────────┐      ┌─────────────────────────┐                 │
│  │ keywords.yaml  │      │    registry/*.json       │                 │
│  │   [STATIC]     │      │    [DYNAMIC]             │                 │
│  │ physics vocab, │      │ models, systems, states, │                 │
│  │ task routing   │      │ algorithms, config_schema│                 │
│  └───────┬────────┘      └───────────┬──────────────┘                │
│          │                           │                               │
│          ▼                           ▼                               │
│  ┌──────────────────────────────────────────────┐                    │
│  │           indexer.py (Runtime Indexer)         │                   │
│  │  Merges static vocab + dynamic registry       │                   │
│  │  into a single searchable index               │                   │
│  └──────────────────────┬────────────────────────┘                   │
│                         │                                            │
│          ┌──────────────┼──────────────┐                             │
│          ▼              ▼              ▼                              │
│  ┌──────────────┐ ┌──────────┐ ┌────────────┐ ┌──────────────┐      │
│  │  discovery.py │ │builder.py│ │validator.py│ │ executor.py  │      │
│  │              │ │          │ │            │ │              │      │
│  │ search       │ │ build    │ │ validate   │ │ submit       │      │
│  │ get_schema   │ │ config   │ │ config     │ │ simulation   │      │
│  │ suggest_algo │ │ fill     │ │ against    │ │ check status │      │
│  │              │ │ defaults │ │ registry   │ │              │      │
│  └──────────────┘ └──────────┘ └────────────┘ └──────┬───────┘      │
│        [YOU]        [DONE]        [DONE]        [YOU] │              │
│                                                       │              │
└───────────────────────────────────────────────────────┼──────────────┘
                                                        │ HTTP
                                                        ▼
                                               Julia Pipeline Server
```

**[DONE]** = Nishan built it. **[YOU]** = Your deliverable.

---

## File Structure

```
mcp_bridge/
├── README.md                       ← you are here
├── __init__.py
│
├── server.py                       [YOU] MCP entry point, tool registration
├── config.py                       [YOU] Paths to registry, Julia server URL
│
├── index/
│   ├── __init__.py
│   ├── keywords.yaml               [DONE] Static physics vocabulary (6 sections)
│   └── indexer.py                  [YOU]  Merges keywords + registry → searchable index
│
├── registry/
│   └── loader.py                   [YOU] Reads & caches the 5 registry JSON files
│
├── tools/
│   ├── __init__.py
│   ├── builder.py                  [DONE] build_config, fill_defaults, build_analysis_config
│   ├── validator.py                [DONE] validate_config
│   ├── test_builder_validator.py   [DONE] Verification suite (all tests pass)
│   ├── discovery.py                [YOU]  search_registry, get_model_schema, suggest_algorithm
│   └── executor.py                 [YOU]  submit_simulation, check_status
│
└── requirements.txt                [YOU] mcp, pyyaml, httpx
```

---

## What Has Been Built (Nishan's Deliverables)

### 1. Registry Updates

Three existing registry files were updated with structured machine-readable fields:

**`registry/models.json`** — Added two things:
- **`dtype_logic`** on every prebuilt model. Three rule patterns:
  - `all_in`: direction params must be in allowed set → `{"all_in": {"params": ["coupling_dir", "field_dir"], "allowed": ["X", "Z"]}}`
  - `all_zero`: value params must equal 0 → `{"all_zero": {"params": ["Jy", "hy"]}}`
  - Both produce `"Float64"` when satisfied, `"ComplexF64"` otherwise
- **Structured `conditional_fields`** in custom model term types (EDCoupling):
  ```json
  "conditional_fields": {
    "range": {
      "required_when": {"pattern": ["finite_range", "finite_range_periodic"]},
      "type": "int", "minimum": 1
    },
    "alpha": {
      "required_when": {"pattern": ["power_law"]},
      "type": "float", "minimum": 0.0
    }
  }
  ```

**`registry/algorithms.json`** — Added two things:
- **`tasks`** block in `algorithm_selection_guide` — maps task types (ground_state, time_evolution, spectrum, imaginary_time) to candidate algorithms with `when` conditions:
  ```json
  "tasks": {
    "ground_state": {
      "candidates": [
        {"algorithm": "dmrg", "when": "N > ed_limit", "category": "tensor_network"},
        {"algorithm": "ed_spectrum", "when": "N <= ed_limit", "category": "exact_diagonalization"}
      ]
    }
  }
  ```
- **`constraint_logic`** on `ed_spectrum.params.use_sparse`: `{"if": {"use_sparse": true}, "then_required": ["n_states"]}`

**`registry/states.json`** — Replaced prose `algorithm_requirement` with structured booleans:
```json
"algorithm_requirement": {
  "ed_spectrum":       {"requires_state": false},
  "dmrg":              {"requires_state": true},
  "tdvp":              {"requires_state": true},
  "ed_time_evolution": {"requires_state": true}
}
```

### 2. `registry/config_schema.json` (NEW)

This is the 5th registry file. The 4 domain registries define **WHAT** is available; this file defines **HOW** to assemble it. It captures all structural conventions so that builder.py and validator.py contain zero hardcoded backend knowledge.

Key sections:

| Section | Purpose |
|---------|---------|
| `backend_categories.mapping` | algorithm → "tensor_network" or "exact_diagonalization" |
| `model_assembly.prebuilt.system_fields_to_copy` | which system fields go into model.params per system type |
| `model_assembly.custom[backend][system_type]` | format_key (channels vs terms), model_name, extra_params, spinboson_sub_keys |
| `state_assembly.custom[backend][system_type]` | site_field name (spin_label vs site_configs), location (root vs params) |
| `state_assembly.random[backend]` | whether to include bond_dim |
| `state_assembly.prebuilt.polarized_eigenstate_field` | eigenstate vs spin_eigenstate per system type |
| `algorithm_assembly.flat_param_mapping[algo]` | maps flat user params (chi_max) → nested paths (options.chi_max) |
| `algorithm_assembly.solver_defaults[algo]` | fixed solver type strings |
| `algorithm_assembly.auto_derived_fields` | computed fields (local_dim from system.S) |
| `analysis_assembly.selection_key[algo]` | sweeps / steps / states |
| `dtype_resolution.custom_model_scan` | how to scan operators for dtype safety |

**Why this matters**: Without it, builder.py would need `if algo in ("dmrg", "tdvp")`, `if system_type == "spin": copy N`, etc. With it, adding a 5th algorithm or changing a field name requires only a JSON edit — zero Python changes.

### 3. `mcp_bridge/index/keywords.yaml`

Static physics vocabulary. Six sections:

| Section | Maps | Example |
|---------|------|---------|
| `task_routing` | phrases → task keys | "ground state" → ground_state |
| `system_detection` | phrases → system type | "cavity" → spinboson |
| `physics_vocabulary` | jargon → params | "ferromagnetic" → J < 0 |
| `operator_vocabulary` | terms → operator symbols | "magnetization" → Z |
| `state_vocabulary` | phrases → state configs | "all up" → polarized(eigenstate=2) |
| `dtype_hints` | operator → dtype requirement | Y, Sp, Sm → ComplexF64 |

Your `indexer.py` merges this with the live registry at runtime.

### 4. `mcp_bridge/tools/builder.py`

Config assembly engine. Every decision reads from the 5 JSON registry files.

**Public API**:

```python
def build_config(
    registry: dict,          # All 5 files: models, systems, states, algorithms, config_schema
    system: dict,            # User system params (partial OK — defaults filled)
    model: dict,             # User model params (partial OK — defaults filled)
    algorithm: dict,         # User algorithm params (partial OK — defaults filled)
    state: dict | None = None,
    description: str = "",
    mode: str = "simulation"
) -> dict:
    """Returns complete config dict ready for Julia runner."""

def fill_defaults(registry: dict, partial_config: dict) -> dict:
    """Takes a partial config, fills missing defaults from registry."""

def build_analysis_config(
    registry: dict,
    simulation_config: dict,
    selection: dict,         # e.g. {"sweeps": [1, 5, 10]}
    observable: dict         # e.g. {"type": "expectation", "operator": "Z"}
) -> dict:
    """Returns analysis config dict."""
```

**What it does internally** (all registry-driven):
- Builds system block: reads `systems.json → system_types[type].fields` for defaults
- Builds model block: dispatches to prebuilt / custom / user-registered handlers
- Resolves dtype automatically: evaluates `dtype_logic` rules (prebuilt) or scans operators against `systems.json → spin_operators` (custom)
- Builds algorithm block: reads `flat_param_mapping` from config_schema to nest flat user params; injects solver defaults; computes auto-derived fields (local_dim)
- Builds state block: checks `requires_state` from states.json; dispatches to random/prebuilt/custom handlers using config_schema conventions

### 5. `mcp_bridge/tools/validator.py`

Config validation engine. Returns structured error/warning reports.

**Public API**:

```python
def validate_config(
    registry: dict,       # All 5 files
    config: dict,
    mode: str = "simulation"
) -> dict:
    """Returns {"valid": bool, "errors": [...], "warnings": [...]}"""
    # Each error: {"code": str, "message": str, "path": str}
```

**Error codes**:
| Code | Meaning |
|------|---------|
| `MISSING_FIELD` | Required field absent |
| `INVALID_TYPE` | Wrong Python type (int vs float vs str) |
| `OUT_OF_RANGE` | Value below minimum or above maximum |
| `INVALID_VALUE` | Value not in allowed set |
| `DTYPE_UNSAFE` | Float64 used with complex-requiring operators |
| `STATE_REQUIRED` | Algorithm needs a state block, none provided |
| `STATE_FORBIDDEN` | Algorithm doesn't use a state, one was provided |
| `SIZE_EXCEEDS_LIMIT` | System size N exceeds algorithm's limit |
| `SPARSE_REQUIRES_NSTATES` | use_sparse=true without n_states |
| `CONDITIONAL_FIELD_MISSING` | Coupling pattern requires range/alpha, not provided |
| `ARRAY_LENGTH_MISMATCH` | Custom state array length doesn't match N |
| `UNKNOWN_MODEL` | Model name not in any registry section |
| `UNKNOWN_ALGORITHM` | Algorithm name not in algorithms.json |

---

## What You Need to Build

### 1. `config.py` — Configuration

Paths and settings. Straightforward.

```python
# Suggested structure:
REGISTRY_DIR = Path(__file__).parent.parent / "registry"  # or however you want to resolve
JULIA_SERVER_URL = "http://localhost:8080"
KEYWORDS_PATH = Path(__file__).parent / "index" / "keywords.yaml"

REGISTRY_FILES = {
    "models":        REGISTRY_DIR / "models.json",
    "systems":       REGISTRY_DIR / "systems.json",
    "states":        REGISTRY_DIR / "states.json",
    "algorithms":    REGISTRY_DIR / "algorithms.json",
    "config_schema": REGISTRY_DIR / "config_schema.json",
}
```

### 2. `registry/loader.py` — Registry Loader

Reads and caches all 5 JSON files into a single dict. This is the `registry` dict that builder.py and validator.py expect.

**Contract**: Must return a dict with exactly these keys:
```python
registry = {
    "models":        <models.json contents>,
    "systems":       <systems.json contents>,
    "states":        <states.json contents>,
    "algorithms":    <algorithms.json contents>,
    "config_schema": <config_schema.json contents>,
}
```

Considerations:
- Cache the parsed JSON — these files rarely change during a session
- Optionally watch for file modifications (user may register new models via GUI mid-session)
- The registry dir is at `<project_root>/registry/`, not inside `mcp_bridge/`

### 3. `index/indexer.py` — Search Index Builder

Merges `keywords.yaml` (static physics vocab) with live registry data into a single searchable index.

**Inputs**:
- `keywords.yaml` — 6 sections of static mappings (see above)
- `registry` dict — the live registry from loader.py

**Output**: A search index that `discovery.py` queries. Structure is up to you — could be an inverted index, a flat list with TF-IDF, or whatever works for fuzzy matching.

**What to index from the registry** (dynamically):
- All prebuilt model names + their descriptions from `models.json → prebuilt_models`
- All custom model term type names from `models.json → custom_models`
- All user-registered model names from `models.json → user_models.models`
- All prebuilt state names + descriptions from `states.json → state_types.prebuilt.patterns`
- All user-registered state names from `states.json → user_states.states`
- All algorithm names + descriptions from `algorithms.json → algorithms`
- All task names + descriptions from `algorithms.json → algorithm_selection_guide.tasks`
- Spin operator names from `systems.json → spin_operators.operators`
- Boson operator names from `systems.json → boson_operators`

**What to index from keywords.yaml** (statically):
- All phrase→key mappings in all 6 sections

**Key property**: When a user registers "my_frustrated_chain" via the GUI, it appears in `models.json → user_models`. Your indexer picks it up on next rebuild — no keywords.yaml update needed.

### 4. `tools/discovery.py` — Discovery Tools

MCP tools that the LLM calls to explore available models/algorithms/states.

**Suggested tools**:

```python
def search_registry(query: str) -> list[dict]:
    """Fuzzy search across the merged index.
    Returns ranked matches with relevance scores.
    Each match: {"type": "model"|"state"|"algorithm"|"concept",
                 "name": str, "description": str, "score": float}
    """

def get_model_schema(model_name: str) -> dict:
    """Return full spec for a model: params, defaults, constraints, hamiltonian.
    Look up in: prebuilt_models → custom_models → user_models (in that order).
    """

def get_algorithm_schema(algorithm_name: str) -> dict:
    """Return full spec: config_structure, params with defaults/bounds, system limits."""

def get_state_schema(state_type: str) -> dict:
    """Return state pattern spec: required params, defaults, examples."""

def suggest_algorithm(task: str, N: int, S: float = 0.5) -> dict:
    """Recommend algorithm based on task and system size.
    Read algorithms.json → algorithm_selection_guide.tasks[task].candidates.
    Read systems.json → constraints_by_algorithm for N limits.
    Return: {"algorithm": str, "reason": str, "template": dict}
    """
```

**Where the data comes from** (all from registry, never hardcoded):
- Model schemas: `registry["models"]["prebuilt_models"][name]`, `registry["models"]["custom_models"]`, `registry["models"]["user_models"]`
- Algorithm schemas: `registry["algorithms"]["algorithms"][name]`
- State schemas: `registry["states"]["state_types"]`
- Task routing: `registry["algorithms"]["algorithm_selection_guide"]["tasks"]`
- System size limits: `registry["systems"]["constraints_by_algorithm"]`

### 5. `tools/executor.py` — Execution Tools

Submit configs to the Julia server and poll status.

```python
def submit_simulation(config: dict) -> dict:
    """POST config to Julia server.
    Endpoint: POST {JULIA_SERVER_URL}/api/run
    Body: JSON config
    Returns: {"tracking_id": str, "status": "queued"|"running"}
    """

def check_status(tracking_id: str) -> dict:
    """GET status from Julia server.
    Endpoint: GET {JULIA_SERVER_URL}/api/status/{tracking_id}
    Returns: {"status": "running"|"completed"|"failed", "message": str, "result"?: dict}
    """
```

The Julia server already exposes these REST endpoints (see `pipeline_server.jl`). You just need to call them via HTTP.

### 6. `server.py` — MCP Server Entry Point

Registers all tools with the MCP protocol so the LLM can call them.

**What to register as MCP tools**:
| Tool Name | Function | Source |
|-----------|----------|--------|
| `search_registry` | `discovery.search_registry` | discovery.py |
| `get_model_schema` | `discovery.get_model_schema` | discovery.py |
| `get_algorithm_schema` | `discovery.get_algorithm_schema` | discovery.py |
| `get_state_schema` | `discovery.get_state_schema` | discovery.py |
| `suggest_algorithm` | `discovery.suggest_algorithm` | discovery.py |
| `build_config` | `builder.build_config` | builder.py [DONE] |
| `fill_defaults` | `builder.fill_defaults` | builder.py [DONE] |
| `build_analysis_config` | `builder.build_analysis_config` | builder.py [DONE] |
| `validate_config` | `validator.validate_config` | validator.py [DONE] |
| `submit_simulation` | `executor.submit_simulation` | executor.py |
| `check_status` | `executor.check_status` | executor.py |

Each tool registration should include a JSON schema describing its input params — the LLM uses this to know what arguments to pass.

**Important**: The builder and validator both expect a `registry` dict as their first argument. Your server.py should load the registry once (via loader.py) and inject it when calling these functions. The LLM never passes the registry — it passes system/model/algorithm/state dicts, and your server glues in the registry.

Example wrapper:

```python
# In server.py tool handler for build_config:
@server.tool("build_config")
async def handle_build_config(system: dict, model: dict, algorithm: dict,
                               state: dict = None, description: str = ""):
    registry = loader.get_registry()  # cached
    return builder.build_config(registry, system, model, algorithm, state, description)
```

---

## Conversation Flow (End-to-End Example)

```
User: "Find the ground state of a 20-site Heisenberg chain with Jz=2"

┌─── Step 1: Discovery ───────────────────────────────────────────────┐
│ LLM calls: search_registry("heisenberg ground state")              │
│                                                                     │
│ Your indexer matches:                                               │
│   keywords.yaml: "ground state" → task_key=ground_state            │
│   registry:      "heisenberg" → prebuilt model                     │
│                                                                     │
│ Returns: [{type: "model", name: "heisenberg", score: 0.95}, ...]   │
└─────────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─── Step 2: Algorithm Selection ─────────────────────────────────────┐
│ LLM calls: suggest_algorithm(task="ground_state", N=20, S=0.5)     │
│                                                                     │
│ Your code reads:                                                    │
│   algorithms.json → tasks.ground_state.candidates                  │
│   systems.json → constraints_by_algorithm (N=20 > ed_limit=14)     │
│                                                                     │
│ Returns: {algorithm: "dmrg", reason: "N=20 exceeds ED limit"}      │
└─────────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─── Step 3: Config Assembly ─────────────────────────────────────────┐
│ LLM calls: build_config(                                           │
│   system    = {type: "spin", N: 20},                               │
│   model     = {name: "heisenberg", params: {Jz: 2}},              │
│   algorithm = {type: "dmrg"}                                       │
│ )                                                                   │
│                                                                     │
│ builder.py (already built):                                        │
│   → Fills system defaults: S=0.5                                   │
│   → Fills model defaults: Jx=1, Jy=1, hx=0, hy=0, hz=0           │
│   → Resolves dtype: Jy=1≠0 → ComplexF64                           │
│   → Fills algorithm defaults: chi_max=128, n_sweeps=10, etc.      │
│   → Adds random state (DMRG requires_state=true)                  │
│                                                                     │
│ Returns: complete JSON config                                      │
└─────────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─── Step 4: Validation ──────────────────────────────────────────────┐
│ LLM calls: validate_config(config)                                 │
│                                                                     │
│ validator.py (already built):                                      │
│   → Checks all fields present, correct types, within bounds        │
│   → Checks dtype consistency with operators                        │
│   → Checks system size within algorithm limits                     │
│                                                                     │
│ Returns: {valid: true, errors: [], warnings: []}                   │
└─────────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─── Step 5: Execution ───────────────────────────────────────────────┐
│ LLM calls: submit_simulation(config)                               │
│                                                                     │
│ Your executor.py:                                                  │
│   → POST config to Julia server /api/run                           │
│   → Returns tracking_id                                            │
│                                                                     │
│ LLM calls: check_status(tracking_id)                               │
│   → GET /api/status/{id}                                           │
│   → Returns results when done                                      │
└─────────────────────────────────────────────────────────────────────┘
```

---

## The Registry (Source of Truth)

The entire pipeline is **registry-driven**. No backend knowledge is hardcoded in Python. Here are the 5 registry files:

```
registry/
├── models.json         # Prebuilt models (5), custom model grammars (2),
│                       # user-registered models, dtype_logic rules
├── systems.json        # System types (spin, spinboson), required fields,
│                       # operator catalogs, Hilbert space constraints
├── states.json         # Prebuilt state patterns, user states,
│                       # algorithm_requirement (requires_state booleans)
├── algorithms.json     # Algorithm configs, params with defaults/bounds,
│                       # task routing, constraint_logic
└── config_schema.json  # Assembly conventions: how to map registry data
                        # into config JSON structure (NEW)
```

### Static vs Dynamic Knowledge

```
keywords.yaml (STATIC)              registry/*.json (DYNAMIC)
─────────────────────               ─────────────────────────
Ships with the tool,                Grows as users register
rarely changes                      new models and states

"ferromagnetic" → J < 0             models.json: 5 prebuilt + N user models
"ground state" → ground_state       algorithms.json: 4 algorithms + task routing
"cavity" → spinboson                states.json: prebuilt patterns + user states
"magnetization" → Z                 systems.json: operator catalogs
```

When a user registers "my_frustrated_chain" via the GUI, your indexer discovers it automatically — no code changes, no keywords.yaml update.

---

## Design Principles

1. **Registry is the only source of truth.** builder.py and validator.py contain zero hardcoded model names, algorithm names, parameter names, or backend conventions. If you grep for "dmrg" or "heisenberg" in builder.py, you'll find nothing.

2. **config_schema.json is the assembly manual.** The 4 domain registries define what models/states/algorithms exist. config_schema.json defines how to structurally assemble them into configs. This separation keeps domain registries clean and builder code generic.

3. **Zero code changes for new components.** Adding a new prebuilt model = edit models.json. Adding a new algorithm = edit algorithms.json + config_schema.json. No Python changes.

4. **Both UI paths produce identical configs.** The HTML GUI and the MCP chat path generate the exact same JSON structure. The Julia server accepts either.

---

## How to Call the Existing Code

### Builder

```python
from mcp_bridge.tools.builder import build_config, fill_defaults, build_analysis_config

# registry = loader.get_registry()  ← your loader provides this

# Build from scratch
config = build_config(
    registry,
    system={"type": "spin", "N": 20},
    model={"name": "heisenberg", "params": {"Jz": 2}},
    algorithm={"type": "dmrg"},
    state={"type": "random", "bond_dim": 16},
    description="Test run"
)

# Fill defaults on a partial config
partial = {
    "system": {"type": "spin", "N": 10},
    "model": {"name": "transverse_field_ising"},
    "algorithm": {"type": "dmrg"}
}
complete = fill_defaults(registry, partial)

# Build analysis config
analysis = build_analysis_config(
    registry,
    simulation_config=config,
    selection={"sweeps": [5, 10]},
    observable={"type": "expectation", "operator": "Z"}
)
```

### Validator

```python
from mcp_bridge.tools.validator import validate_config

result = validate_config(registry, config)
# result = {
#   "valid": True,
#   "errors": [],
#   "warnings": [{"message": "...", "path": "..."}]
# }

# On invalid config:
# result = {
#   "valid": False,
#   "errors": [{"code": "OUT_OF_RANGE", "message": "N must be >= 2", "path": "system.N"}],
#   "warnings": []
# }
```

---

## Running the Tests

```bash
cd mcp_bridge/tools
python test_builder_validator.py
```

The test suite verifies:
1. Validator accepts all 5 example configs from `examples/`
2. Builder round-trip: builds 5 different scenarios (DMRG, TDVP, ED spectrum, ED time evolution, custom model)
3. Dtype auto-resolution: 6 cases (TFI Z/X→Float64, TFI Y→Complex, Heisenberg Jy=0→Float64, etc.)
4. Validator error detection: 7 error codes triggered correctly
5. Zero hardcoding: greps builder.py for model/algorithm names — finds none

---

## Julia Server Endpoints

The Julia server (`pipeline_server.jl`) exposes these REST endpoints that executor.py will call:

| Method | Endpoint | Body | Response |
|--------|----------|------|----------|
| POST | `/api/run` | JSON config | `{"run_id": str, "status": "running"}` |
| GET | `/api/status/:run_id` | — | `{"status": str, "message": str}` |
| GET | `/api/catalog` | — | Simulation catalog (JSONL) |
| GET | `/api/catalog-info` | — | Catalog metadata for dynamic filters |
| GET | `/api/observable-catalog-info` | — | Observable catalog metadata |
| GET | `/api/query/simulations?...` | — | Query simulation catalog with filters |
| GET | `/api/query/observables?...` | — | Query observable catalog with filters |
| GET | `/api/results/simulations/:run_id` | — | Simulation results & metadata |
| GET | `/api/results/observables/:run_id` | — | Observable results as JSON |
| POST | `/api/observables/calculate` | Analysis config | Calculate observable on existing data |
| GET | `/api/registry/:name` | — | Raw registry JSON (models/systems/states/algorithms/observables) |
| POST | `/api/registry/models` | Model spec | Register a user model |
| POST | `/api/registry/states` | State spec | Register a user state |
| DELETE | `/api/registry/models/:name` | — | Delete a user model |
| DELETE | `/api/registry/states/:name` | — | Delete a user state |

---

## Suggested Build Order

```
1. config.py           — paths and settings (trivial)
2. loader.py           — read + cache 5 JSON files (straightforward)
3. executor.py         — HTTP calls to Julia server (straightforward)
4. indexer.py          — merge keywords + registry (medium complexity)
5. discovery.py        — search + schema tools (uses indexer)
6. server.py           — wire everything into MCP protocol (final integration)
```

Items 1–3 are independent of each other and can be built in parallel. Item 4 needs loader.py. Item 5 needs indexer.py. Item 6 needs everything.

---

## Questions?

The full pipeline design doc is at `docs/MCP_Pipeline/README.md`. It has additional architecture diagrams, conversation flow examples, and the scalability story.

The registry files themselves are well-documented — each has description fields explaining the purpose of every section. Start by reading `registry/config_schema.json` to understand the assembly conventions.
