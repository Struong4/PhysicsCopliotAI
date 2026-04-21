# Module Abstraction: Physics Co-Pilot Platform

## Context

Physics Co-Pilot is a general AI-assisted platform for computational physics.
**TNCodebase** (tensor networks + ED) is the first module; the second will cover
**1D/2D dynamical systems** (discrete-time maps + continuous-time ODEs). Today
the chatbot, prompt builder, tool schemas, and UI have TN-specific assumptions
baked in. We need to extract a clean **Module** interface so the same
chatbot + UI shell can host any module, with a **runtime dropdown** to switch.

**This plan is design-only.** Execution happens after the 2026-04-23 demo.
Nothing in this document gets implemented now. The TN golden path for the
demo stays untouched.

---

## Goals & non-goals

**Goals**
- Identify the module contract — the minimal API a new module must implement.
- Preserve the current UI shell (chat panel + iframe drawer) exactly.
- Support a runtime dropdown to switch modules; session resets on switch.
- Validate the abstraction against a concrete second module (dynamical systems).
- Follow the JSON-boundary rule: modules are described and communicate via JSON.

**Non-goals**
- No multi-module sessions, tabs, or parallel modules (post-v1).
- No auto-migration of existing data/registries at execution time — TN stays
  structurally identical, just moved under `modules/tensornetwork/`.
- No changes to the Julia engine's internal physics code.
- No new frontend framework — the current HTML/JS shell stays.

---

## Current TN coupling (from exploration)

The TN-specific surface is at seven layers:

| Layer | File | TN-specific bits |
|---|---|---|
| Tool schemas | [chatbot/app.py](chatbot/app.py) L125–396 | `submit_config` schema (system/model/algorithm/state), `calculate_observable` observable types list, `register_model`/`register_state` spin/boson fields |
| Prompt builder | [chatbot/prompt_builder.py](chatbot/prompt_builder.py) L46, 85–103, 177–189, 299–391, 394–470 | Role line ("TNCodebase"), algorithm selection decision tree, physics vocabulary (X/Y/Z/Sp/Sm, Neel, polarized), conversation rules keyed on algorithm names |
| Config validation | [chatbot/app.py](chatbot/app.py) L711–722 | Hardcoded post-processing rules keyed on `dmrg`/`tdvp`/`ed_spectrum`/`ed_time_evolution` |
| Observable rendering | [chatbot/static/index.html](chatbot/static/index.html) L1350–1428 | 5 Plotly functions; selection is shape-based (generic), axis labels are TN-biased ("Site", "Sweep") |
| Engine dispatch | [server/pipeline_server.jl](server/pipeline_server.jl) L94, 857 | Julia server = the only engine; runner functions assume TN config shape |
| Registries | [registry/*.json](registry/) | All six files are pure TN (models, algorithms, states, systems, observables, config_schema) |
| Config builder iframe | [frontend/config_builder.html](frontend/config_builder.html) | Already fairly generic — renders form from `/api/registry/*`. Served by Julia. |

**Structural vs TN-specific split**: the chat/session/polling/drawer machinery
is module-agnostic already. Registries, prompt content, tool schemas, and
engine dispatch are where TN is hardcoded.

---

## Module interface (the contract)

A **Module** is a bundle of:

1. **Identity** (manifest): `id`, `display_name`, `description`, `version`
2. **Engine endpoint**: base URL exposing a fixed REST contract (see below)
3. **Registries**: module-defined JSON files describing its domain
4. **Tool schemas**: JSON files with Claude tool definitions
5. **Prompt materials**: system prompt template + domain vocabulary
6. **Config builder URL**: the iframe URL for the right panel
7. **Observable render spec**: data-shape-to-plot mapping + axis-label overrides

Everything else (chat, sessions, polling, drawer cards, status polling,
deduplication) is shared core code — the chatbot doesn't care which module
is active.

### Required engine REST contract

Every module's engine must expose:

- `POST /api/run` → `{tracking_id}` — accept a config JSON, start a run
- `GET /api/status/{id}` → `{status, last_message, run_id?}` — poll progress
- `GET /api/catalog` → list of past runs with metadata
- `GET /api/result/{run_id}` → run output (module-specific JSON)
- `POST /api/observables/calculate` → `{tracking_id}` — request an observable
- `GET /api/observables/{id}` → observable result
- `GET /api/registry/{name}` → registry JSON by name

The chatbot proxies all of these. Module-specific content flows through as
opaque JSON.

---

## Module manifest format

One JSON file per module, loaded by the chatbot at startup:

```json
{
  "id": "tensornetwork",
  "display_name": "TensorNetwork",
  "subtitle": "Quantum many-body simulation",
  "description": "DMRG / TDVP / exact diagonalization for spin and spin-boson systems.",
  "version": "1.0",
  "engine_url": "http://julia-server:8080",
  "config_builder_url": "http://julia-server:8080/",
  "registries": ["models", "algorithms", "states", "systems", "observables", "config_schema"],
  "tools_file": "tools.json",
  "prompt_file": "prompt.yaml",
  "render_spec_file": "render.json"
}
```

Manifests live at `modules/<id>/manifest.json`. The chatbot discovers modules
by scanning `modules/*/manifest.json`.

---

## Repository layout after refactor

```
modules/
  tensornetwork/
    manifest.json
    tools.json          # Claude tool schemas for TN (submit_config, etc.)
    prompt.yaml         # Role, algorithm guidance, vocabulary, examples
    render.json         # axis-label + obs-type → plot-type overrides
    registry/
      models.json       # (moved from repo root /registry/)
      algorithms.json
      states.json
      systems.json
      observables.json
      config_schema.json

  dynamical_systems/
    manifest.json
    tools.json          # run_trajectory, compute_lyapunov, plot_bifurcation, ...
    prompt.yaml         # ODE/map vocab: attractor, fixed point, Lyapunov, ...
    render.json         # phase_portrait, bifurcation, time_series renderers
    registry/
      maps.json          # logistic, tent, Henon, standard, ...
      odes.json          # Lorenz, Rössler, Duffing, Van der Pol, ...
      integrators.json   # RK4, adaptive, Euler, ...
      observables.json   # trajectory, Lyapunov, Poincaré section, bifurcation, ...
      config_schema.json # (module-specific config shape)

chatbot/                 # unchanged location, but refactored to be module-agnostic
  app.py                 # loads manifests, serves module-agnostic routes
  prompt_builder.py      # templated; pulls module-specific content from manifest
  static/index.html      # adds module dropdown; plot renderers driven by render.json
  module_loader.py       # NEW: reads manifests, holds active module state

server/                  # TN engine stays here (it IS the TN module's engine)
ds_server/               # NEW future location for dynamical-systems engine
```

---

## Phased execution (post-demo)

### Phase 0 — File reorganization (no behavior change)

Goal: create the physical structure without any functional change.
Everything still works exactly as today.

- Create `modules/tensornetwork/` directory.
- Move `registry/*.json` → `modules/tensornetwork/registry/*.json`.
- Update `chatbot/app.py` `REGISTRY_DIR` constant to point to the new path
  (one-line change), or keep a symlink for transition.
- Add a minimal `modules/tensornetwork/manifest.json` that encodes today's
  behavior (engine URL from env var, six registries, etc.).
- Verify nothing broke: chatbot still starts, TN golden path still works.

### Phase 1 — Extract TN-specific content from chatbot code

Goal: the chatbot holds **no** TN-specific strings.

- Move TN tool schemas from `app.py` (L125–396) → `modules/tensornetwork/tools.json`.
- Move prompt-builder TN vocabulary / examples / rules (from
  `prompt_builder.py` L85–103, 299–391, 394–470) → `modules/tensornetwork/prompt.yaml`.
- Refactor `prompt_builder.py` to accept a `module_config` arg and splice in
  content from `prompt.yaml` + the module's registries.
- Refactor `app.py` tool-definition code to load tool schemas from the module.
- Generalize post-processing rules at L711–722: move them to
  `config_schema.json` (e.g. `"config_rules": {"system_N_to_model_params": true}`)
  and apply them generically.
- The chatbot becomes module-agnostic; only one module exists so there's still
  no dropdown.

### Phase 2 — Module dropdown in UI

Goal: support picking a module at runtime with a session reset.

- Add a `GET /api/modules` endpoint in `app.py` returning the list of loaded
  manifests.
- Add a module dropdown in [chatbot/static/index.html](chatbot/static/index.html)
  header (next to "Physics Co-Pilot –"). Shows `display_name` from manifests.
- On dropdown change: clear the session, re-fetch prompt + registries for the
  new module, update the subtitle, point the right iframe to the new
  `config_builder_url`.
- Introduce `render.json` per module: `{"default_x_label": "Sweep",
  "default_y_label": "Site", "overrides": {<obs_type>: {...}}}`. Plot
  renderers in index.html read from it instead of hardcoding "Site"/"Sweep".
- With just TN in the dropdown this is still zero behavior change for TN.

### Phase 3 — Dynamical systems module

Goal: validate the abstraction by actually adding module #2.

- Create `modules/dynamical_systems/` with manifest + registries + tools +
  prompt + render spec. (Pure JSON/YAML authoring — no new chatbot code.)
- Build a new engine service `ds_server/` (Python + numpy/scipy, simpler than
  TN). It only has to implement the seven REST endpoints above. Expected size:
  few hundred lines.
- Its registries:
  - `maps.json` — logistic, tent, Henon, standard map, Arnold cat, …
  - `odes.json` — Lorenz, Rössler, Duffing, Van der Pol, Lotka-Volterra, …
  - `integrators.json` — RK4, DOPRI5, Euler (for ODEs); direct iteration for maps
  - `observables.json` — trajectory, phase_portrait, Lyapunov, Poincaré section,
    bifurcation_diagram, power_spectrum, return_map
  - `config_schema.json` — shape: `{system: {type, dim}, model: {name, params},
    initial_condition: [...], time: {t0, tf, dt|n_steps}, algorithm: {type, ...}}`
- Add matching plot renderers: `_plotPhasePortrait2D`, `_plotBifurcation`,
  `_plotReturnMap`. Wire via `render.json` rather than hardcoded.
- Add a Docker service for `ds_server` in `docker-compose.yml`.
- User flow: pick "Dynamical Systems" in the dropdown, type "simulate the
  Lorenz attractor for 50 time units", see the 3D phase portrait.

### Phase 4 — Polish

- Session reset UX: a small confirmation when the user has in-flight runs.
- Module-specific welcome message (from `prompt.yaml`).
- Module-specific placeholder examples in chat input.
- Catalog scoping: the catalog view shows only runs from the active module.

---

## Validation: the "Lorenz in 60 seconds" test

When Phase 3 is done, the following should work end-to-end with zero code
changes in `chatbot/` for each new module thereafter:

1. Open the app. Dropdown shows "TensorNetwork" and "Dynamical Systems".
2. Select "Dynamical Systems". Subtitle updates, iframe loads DS config builder,
   chat welcome message updates.
3. Type: *"Simulate the Lorenz system with σ=10, ρ=28, β=8/3 for 50 time units"*.
4. Claude generates a config using DS tool schemas + DS registries.
5. Confirm & Run → DS engine integrates → status poll → result JSON returned.
6. Ask: *"Plot the 3D phase portrait"* → Plotly renders an attractor.
7. Switch back to "TensorNetwork" → session resets → TN golden path still works.

If this flow works without editing any chatbot/*.py file after Phase 2, the
abstraction has succeeded.

---

## Key risks & mitigations

- **Config shape divergence**: TN config is `{system, model, algorithm, state}`;
  DS will be `{system, model, initial_condition, time, algorithm}`. The
  chatbot must not assume any top-level keys — validation and post-processing
  rules live in `config_schema.json` per module. *Mitigation*: make the `state`
  top-level key optional; treat config as opaque JSON in the chatbot.

- **Observable rendering complexity**: DS observables like "bifurcation
  diagram" don't fit the current 5 plot types. *Mitigation*: `render.json`
  lets modules declare new render functions; add them to `index.html` as
  needed. The dispatcher remains data-shape-based with module overrides.

- **Prompt bloat**: as modules pile up, prompt content can grow. *Mitigation*:
  only the active module's `prompt.yaml` is loaded per session (session reset
  on switch enforces this).

- **Demo stability during refactor**: Phase 0 is zero-behavior-change; each
  subsequent phase keeps the TN golden path working. *Mitigation*: after
  every phase, run the TN demo flow end-to-end; don't ship a phase that
  breaks it.

---

## Verification (post-execution)

1. **Phase 0 check**: `docker compose up`, open localhost:8000, run a
   Heisenberg DMRG simulation → identical UX, no regressions.
2. **Phase 1 check**: same test + `git grep -i "dmrg\|heisenberg\|spin"
   chatbot/*.py` returns zero matches outside of comments.
3. **Phase 2 check**: dropdown visible, TN is selected by default, switching
   to TN (only option) leaves state clean.
4. **Phase 3 check**: the "Lorenz in 60 seconds" test above passes.
5. **Phase 4 check**: active-module context is clear from the UI at every step.

---

## Open questions to revisit at execution time

- Where do DS runs' data get stored? Separate `data_ds/` vs shared `data/`
  with a `module_id` tag in the catalog entry?
- Should `render.json` embed renderer logic (risky — code in JSON) or just
  name built-in renderers that must be defined in `index.html`? Recommend
  the latter.
- Authentication / permissions if modules get deployed to Amazon infra
  post-demo. Out of scope for v1.
