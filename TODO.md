# TODO

## Vision

**Physics Co-Pilot** is intended as a general AI-assisted platform for
computational physics. **TNCodebase** (tensor networks + exact diagonalization)
is the first module. Future modules may cover other physics domains
(e.g. molecular dynamics, DFT, Monte Carlo, PDE solvers).

UI branding reflects this: "Physics Co-Pilot – TensorNetwork". Other modules
would plug in the same way, surfacing as their own subtitle (e.g. "Physics
Co-Pilot – Molecular Dynamics").

## Design principles for future modules

- **JSON boundary**: LLMs and rule-based code interact only via JSON (e.g.
  `config.json`). Any new module must expose its configuration and results
  through JSON, never through direct coupling with the chatbot logic.
- **Module-agnostic core**: the chatbot, prompt builder, registry system,
  and frontend should not hardcode TN/ED assumptions where a choice would
  generalize.
- **Registry-driven**: new models/algorithms/observables should be added to
  the existing registry files rather than to the chatbot or engine code.

## Architecture plan

A detailed design for the module abstraction (contract, manifest format,
phased refactor, validation against a dynamical-systems module) is in
[docs/module-architecture.md](docs/module-architecture.md). Execution is
planned for after the 2026-04-23 demo.
