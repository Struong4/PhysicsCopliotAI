# Design Choices: Registry-Driven Architecture

## Overview

TNSoftware uses a **registry-driven architecture** where a central set of JSON registry files acts as the single source of truth that connects the backend (Julia computation engine) with all frontends (HTML GUI, MCP bridge for LLMs, CLI tools). This document explains the architectural pattern, why it was chosen, and how it solves concrete problems in this project.

---

## The Core Idea

```
┌──────────────────┐
│  Julia Backend    │──writes──▶┌──────────────┐◀──reads──┌──────────────────┐
│  (src/)           │           │   Registry   │          │  HTML GUI         │
│                   │           │   (JSON)     │          │  (frontend/)      │
│  Models, States,  │           │              │          └──────────────────┘
│  Algorithms, etc. │           │  models.json │◀──reads──┌──────────────────┐
└──────────────────┘           │  states.json │          │  MCP Bridge       │
                                │  systems.json│          │  (LLM interface)  │
                                │  algorithms. │          └──────────────────┘
                                │    json      │◀──reads──┌──────────────────┐
                                └──────────────┘          │  CLI / Scripts    │
                                                          └──────────────────┘
```

**The registry is the contract between backend and frontend.** The backend declares "here is what I can do" by writing entries to the registry. Any frontend reads the registry to discover what's available, what parameters are needed, what constraints apply, and how to build a valid configuration — without any hardcoded knowledge of specific physics models or algorithms.

Neither side knows about the other directly:
- The backend doesn't care if a request came from a browser click or an LLM
- The frontend doesn't care how DMRG is implemented — it just knows the registry says DMRG needs `n_sweeps`, `chi_max`, `cutoff`

---

## The Problem This Solves

### Problem 1: The Hardcoded HTML GUI

When the config builder GUI (`frontend/config_builder.html`) was first designed, every model, state, algorithm, and parameter was hardcoded directly into the HTML:

```
Hardcoded approach:
┌─────────────────────────────────────────────────┐
│  config_builder.html                            │
│                                                 │
│  <select id="model">                            │
│    <option value="heisenberg">Heisenberg</option│  ← hardcoded
│    <option value="tfi">TFI</option>             │  ← hardcoded
│    <option value="ising_dicke">Ising-Dicke</opt>│  ← hardcoded
│  </select>                                      │
│                                                 │
│  if (model === "heisenberg") {                  │
│    show fields: J, h, coupling_dir, field_dir   │  ← hardcoded
│  }                                              │
│  if (model === "tfi") {                         │
│    show fields: J, h                            │  ← hardcoded
│  }                                              │
│  ...                                            │
└─────────────────────────────────────────────────┘
```

**Consequences:**
- Every new model required manually editing HTML — adding `<option>` tags, writing conditional field logic, adding validation
- The HTML had to know every parameter name, type, default, and constraint for every model
- If the Julia backend added a new model, the GUI was broken until someone hand-updated the HTML
- Prebuilt models and user-registered models followed completely different code paths

### Problem 2: LLM Access via MCP

The MCP (Model Context Protocol) bridge allows LLMs to build and run simulation configs through natural language. An LLM cannot read hardcoded HTML. It needs structured, machine-readable data to understand what options exist and how to compose a valid config.

If the GUI is the only place where model-parameter mappings are defined, the MCP bridge would need to duplicate all that knowledge — creating two parallel, manually-synchronized definitions of the same information.

### The Common Root Cause

Both problems stem from the same issue: **domain knowledge (what models exist, what parameters they need) was embedded inside a specific consumer** (the HTML file) instead of being declared in a neutral, shared location.

---

## The Solution: Registry as Single Source of Truth

### Registry Structure

TNSoftware maintains four registry files in `registry/`:

| File | Purpose |
|------|---------|
| `models.json` | All available models — prebuilt and user-registered. Each entry declares: display name, system type, required/optional params, param types, defaults, constraints, backend function name |
| `systems.json` | Physical system types (spin, spinboson). Declares: required fields, allowed values, dtype rules, local dimension derivation |
| `states.json` | Initial state types (random, polarized, Néel, custom, etc.). Declares: which algorithms need states, params per state type, backend function mapping |
| `algorithms.json` | Algorithms (DMRG, TDVP, ED). Declares: full config structure, all param specs with types/defaults/constraints, which system types are supported |

### What the Registry Contains

Each entry is self-describing. For example, a model entry includes:

```json
{
  "heisenberg": {
    "display_name": "Heisenberg",
    "system_type": "spin",
    "required_params": ["J", "h", "coupling_dir", "field_dir"],
    "optional_params": [],
    "params": {
      "J": {
        "type": "float",
        "default": 1.0,
        "description": "Coupling strength"
      },
      "coupling_dir": {
        "type": "string",
        "allowed_values": ["X", "Y", "Z"],
        "default": "Z",
        "dtype_constraint": "If Y, dtype must be ComplexF64."
      }
    },
    "dtype_rule": "Float64 safe only when coupling_dir and field_dir are both in {X, Z}.",
    "backend_function": { "tn": "_get_heisenberg_channels", "ed": "_get_heisenberg_terms" },
    "example_config": { ... }
  }
}
```

This single entry contains everything any consumer needs: parameter names, types, defaults, allowed values, constraints, display names, and even example configs.

### How Consumers Use It

**HTML GUI (registry-driven approach):**
```
On page load:
  1. Fetch models.json, systems.json, states.json, algorithms.json
  2. Build model dropdown from models.json keys
  3. When user selects a model → read its params → generate form fields dynamically
  4. Apply constraints from registry (allowed_values → dropdown, type → input type)
  5. On submit → assemble config JSON from form values
```

**MCP Bridge (LLM interface):**
```
On tool call:
  1. Load registry into memory
  2. LLM asks "what models are available?" → return models.json keys
  3. LLM says "use heisenberg with J=1.0" → look up heisenberg params, validate, build config
  4. All validation rules come from registry — MCP has zero hardcoded physics knowledge
```

**CLI scripts:**
```
  1. Load registry
  2. Validate user-provided config against registry constraints
  3. Report errors referencing registry specs
```

All three consumers derive their behavior from the same source. None contains hardcoded domain knowledge.

---

## Architecture Evolution

### Phase 1: Fully Hardcoded (Original)

```
Backend ──── [implicit knowledge] ───── HTML GUI
```

- All model/param knowledge lived in the HTML
- Adding a model = editing Julia code + editing HTML
- Only one consumer (browser GUI)

### Phase 2: Hybrid (Current)

```
Backend ──── Registry ───── HTML GUI (reads registry for user-registered items)
                  │              └── still has hardcoded prebuilt items
                  │
                  └──────── (MCP bridge planned)
```

- Registry added for user-registered models and states
- Prebuilt models still hardcoded in HTML
- Two code paths: hardcoded path for prebuilt, dynamic path for user-registered
- Inconsistent behavior between the two paths

### Phase 3: Fully Registry-Driven (Target)

```
Backend ──── Registry ──┬── HTML GUI (fully dynamic)
                        ├── MCP Bridge (fully dynamic)
                        └── CLI / scripts (fully dynamic)
```

- Registry is the only place models/params are defined
- HTML GUI becomes a generic "registry renderer"
- All consumers follow identical code paths
- Adding a model = one registry entry, zero frontend changes

---

## Benefits

### Single Maintenance Point
Add a model to the registry → it appears in every frontend automatically. No HTML surgery, no MCP updates, no CLI changes.

### Zero-Coordination Development
The person writing Julia physics code and the person building UI never need to synchronize. The registry is the interface contract.

### Consistency
Prebuilt and user-registered models follow identical rendering, validation, and config generation paths. No split behavior.

### Extensibility
New frontends (Jupyter widget, mobile app, Slack bot, batch scheduler) just read the same registry. The backend never knows or cares.

### User Registration
When a user registers a custom model via the GUI, it lands in the registry. Immediately available to every consumer — including LLMs via MCP.

### Testability
Validate a config against the registry programmatically. No need to click through a GUI to check if a config is valid.

---

## Tradeoffs

### Upfront Registry Design
The registry schema must be expressive enough to describe all current and future options. If the schema is too rigid, new features require schema changes. TNSoftware mitigates this with flexible fields like `params` (arbitrary key-value), `constraints` (declarative rules), and `example_config` (concrete samples).

### Generic vs. Bespoke UX
A hardcoded form can have hand-tuned UX — custom tooltips, specific field ordering, contextual help. A fully dynamic form is more generic. This is mitigated by adding `description`, `display_name`, and `display_order` fields to registry entries, but it requires discipline to keep registry entries well-documented.

### Complex Conditional Logic
Some form interactions are hard to express declaratively (e.g., "show field X only when model is long-range AND algorithm is TDVP"). The registry needs a constraint language for cross-block dependencies. TNSoftware's registry already has `dtype_rule`, `requires_system`, `algorithm_requirement`, and `required_for` / `not_used_for` fields that handle most cases.

### Schema Evolution
As the registry grows, backward compatibility matters. Adding new fields is safe (old consumers ignore them), but renaming or removing fields can break consumers. Versioning the registry (`"version": "1.0.0"` in each file) helps manage this.

---

## Well-Known Software Using This Pattern

This architecture is not novel — it is a well-established pattern used across industry and science. The following are notable implementations grouped by domain.

### API Specification Layer

| Software | How It Uses the Pattern |
|----------|------------------------|
| **OpenAPI / Swagger** | A JSON/YAML spec defines all API endpoints, schemas, and parameters. Server stubs, client SDKs, documentation, and validation are all generated from this single spec. Used by Google, Stripe, Microsoft. |
| **GraphQL** | A typed schema on the server describes every query, mutation, and type. All clients introspect or codegen from this schema. Tools like Apollo Codegen auto-generate typed clients. |
| **gRPC / Protocol Buffers** | `.proto` schema files define service interfaces and message types. Compilers generate client and server code in any language from the same proto file. Used internally at Google for decades. |
| **AWS Smithy** | AWS's internal IDL defines the shape of every AWS service API. SDKs in every language, CLI tools, and documentation are all generated from Smithy models. |

### Schema-Driven Form Generators

| Software | How It Uses the Pattern |
|----------|------------------------|
| **react-jsonschema-form (RJSF)** | Takes a JSON Schema and automatically renders a validated HTML form. Field types, validation, labels, and defaults all come from the schema. Used by NASA, Mozilla. |
| **JSON Forms (EclipseSource)** | Separates data schema, UI schema, and renderer registry. Teams swap renderers without touching the data contract. The "renderer registry" concept directly parallels this architecture. |
| **Formly** | All form structure — fields, validation, layout, conditional visibility — described in JSON config. The backend controls the UI shape without frontend code changes. Used in enterprise insurance and healthcare portals. |

### Plugin and Extension Systems

| Software | How It Uses the Pattern |
|----------|------------------------|
| **VS Code Extensions** | Every extension declares its contributions (commands, settings, keybindings) in a `package.json` manifest. VS Code's core reads manifests at load time — no hardcoded knowledge of specific extensions. |
| **Backstage (Spotify)** | Internal developer portal where all capabilities are plugins registered into a central app registry. The registry drives what appears in the UI and what APIs are available. Now a CNCF project. |
| **WordPress Plugins** | 60,000+ plugins registered via structured metadata headers. The CMS discovers capabilities from metadata, not hardcoded references. |

### Infrastructure and Configuration

| Software | How It Uses the Pattern |
|----------|------------------------|
| **Terraform Providers** | Every provider (AWS, GCP, Azure) publishes a machine-readable schema of its resources and attributes. Terraform validates configs, plans changes, and generates docs — all from provider schemas. |
| **Kubernetes CRDs** | Custom Resource Definitions let operators define new resource types using an OpenAPI v3 schema. The API server validates and serves resources using that schema as the sole specification. Foundation for Prometheus, Istio, Argo CD operators. |
| **Ansible Module Specs** | Each module declares its argument spec (parameters, types, defaults, validation). Ansible uses this spec for validation, documentation generation, and CLI interface — all from one declarative definition. |

### Scientific Software

| Software | Domain | How It Uses the Pattern |
|----------|--------|------------------------|
| **HDF5 / NetCDF** | Climate, genomics, physics | Self-describing file formats where the schema (dimensions, variables, types) is embedded in the file. Any tool can discover structure without external docs. |
| **FITS** | Astronomy | Standard since 1981. A header block in every file acts as a self-describing schema. Telescopes worldwide read each other's data because the header is the contract. |
| **CERN ROOT** | High-energy physics | "Streamer info" registry embedded in `.root` files describes C++ class layouts. Maintains backward/forward compatibility across datasets spanning decades. |
| **NWB (NeuroData Without Borders)** | Neuroscience | Formal YAML schema defines all neuroscience data types. APIs in Python, MATLAB, and C++ all read/write data by consulting this schema. Used by Allen Institute, Janelia. |

### Data and Event Systems

| Software | How It Uses the Pattern |
|----------|------------------------|
| **Confluent Schema Registry** | Stores all Avro/Protobuf/JSON schemas centrally for Apache Kafka. Producers and consumers look up schemas at runtime. Enforces compatibility rules across versions. |
| **Apache Iceberg / Delta Lake** | Maintain explicit schema registries per table in metadata files. Schema evolution (add/rename/drop columns) tracked and versioned, allowing safe concurrent access. |

---

## How This Applies to TNSoftware

### The Two Concrete Cases

**Case 1: HTML Config Builder**

The config builder (`frontend/config_builder.html`) needs to present a form that lets users select a model, fill in parameters, and generate a valid `config.json`. Under the registry-driven approach:

- On page load, the GUI fetches all four registry files from the server
- The model dropdown is populated from `models.json` keys
- When the user selects a model, the form fields are generated from that model's `params` object
- Validation rules (allowed values, type checks, dtype constraints) come from the registry
- The GUI knows how to render a dropdown, a number input, a text field — but knows nothing about Heisenberg or Ising specifically

**Case 2: MCP Bridge for LLMs**

The MCP bridge (`mcp_bridge/`) exposes tools that let an LLM build and run simulations through natural language. Under the registry-driven approach:

- The bridge loads registry files into a searchable index
- Tool `list_models` returns model names and descriptions from `models.json`
- Tool `build_config` validates LLM-provided parameters against registry specs
- Tool `validate_config` checks a complete config against all four registries
- The bridge has zero hardcoded physics — all knowledge comes from the registry

**The shared principle:** Both consumers answer the same question — "what can I build and how?" — by reading the same registry files. Neither duplicates or hardcodes domain knowledge.

### The Registry Is Nearly Complete

Analysis of the four registry files confirms they are approximately 100% self-describing:

- **models.json**: Every model lists required params, optional params, types, defaults, allowed values, constraints, dtype rules, system type linkage, and backend function mapping
- **systems.json**: Every system type lists required fields, allowed values, dtype rules, local dimension derivation
- **states.json**: Every state type lists algorithm requirements, params with types/defaults/constraints, backend function mapping per system type
- **algorithms.json**: Every algorithm lists full config structure, all param specs, system type requirements, state requirements

One minor gap: the `n_exp` parameter for long-range TN models lacks a full spec entry in `models.json`. This is a documentation fix, not an architectural issue.

---

## Design Principles

1. **The registry is the only place domain knowledge is defined.** No consumer (GUI, MCP, CLI) should contain hardcoded model names, parameter lists, or validation rules.

2. **Consumers are generic renderers.** The GUI knows how to render form elements. The MCP bridge knows how to map natural language to structured data. Neither knows physics.

3. **Adding a new option is a one-step operation.** Add a registry entry → every consumer picks it up. No coordination, no manual updates, no deployments.

4. **The registry schema is the API contract.** Backend developers and frontend developers agree on registry schema structure. They never need to agree on specific model details.

5. **Registry entries are self-describing.** Each entry contains enough information for any consumer to render, validate, and build a config without external documentation.

6. **Backward compatibility through additive changes.** New registry fields are added, never renamed or removed. Consumers ignore fields they don't understand. Version numbers track breaking changes.

---

## Summary

The registry-driven architecture decouples TNSoftware's Julia computation engine from its frontends by placing a shared, structured, self-describing registry between them. This is the same pattern used by OpenAPI (APIs), Terraform (infrastructure), Kubernetes CRDs (orchestration), react-jsonschema-form (UIs), and CERN ROOT (scientific data) — all systems that need a single source of truth consumed by multiple independent clients.

For TNSoftware, this means:
- The HTML GUI, MCP bridge, and any future interface all derive their behavior from the same four JSON files
- New physics models, states, and algorithms propagate to all interfaces with zero frontend changes
- The architecture scales to new consumers, new users, and new physics without structural modification
