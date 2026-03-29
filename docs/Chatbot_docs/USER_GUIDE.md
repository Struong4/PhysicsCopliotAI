# User Guide

## Table of Contents
1. [UI Layout](#ui-layout)
2. [Conversation Flow](#conversation-flow)
3. [Supported Models](#supported-models)
4. [Algorithms](#algorithms)
5. [Initial States](#initial-states)
6. [Config Review Workflow](#config-review-workflow)
7. [Session Persistence](#session-persistence)
8. [Deduplication](#deduplication)

---

## UI Layout

The interface is split into two panels:

| Panel | Purpose |
|-------|---------|
| **Left — Chat** | Conversational interface with Claude |
| **Right — Config** | Displays the proposed simulation config for review and confirmation |

The right panel is blank until Claude has gathered enough information to build a complete config.

---

## Conversation Flow

Claude guides you through parameter collection one or two questions at a time. The flow is:

```
You describe a simulation
    → Claude asks clarifying questions (model type, N, algorithm, state)
    → Config appears in the right panel
    → You review, optionally edit, then confirm
    → Julia runs the simulation
    → Claude interprets the results
    → You can ask follow-up questions or request a new simulation
```

**Useful shorthand the chatbot understands:**
- "ground state" or "energy spectrum" → `ed_spectrum`
- "dynamics", "quench", or "time evolution" → `ed_time_evolution`
- "Ising" (unqualified) → `transverse_field_ising`

---

## Supported Models

The chatbot supports three models, all via Exact Diagonalization (N ≤ 14 sites).

<details>
<summary><strong>Transverse Field Ising</strong></summary>

```
H = J Σ σ_coupling(i) σ_coupling(i+1) + h Σ σ_field(i)
```

Parameters to provide:
- `N` — number of sites (≤ 14)
- `J` — coupling strength (e.g. `-1` for ferromagnet)
- `h` — field strength
- `coupling_dir` — spin direction of the interaction: `"X"`, `"Y"`, or `"Z"`
- `field_dir` — spin direction of the field: `"X"`, `"Y"`, or `"Z"`

Typical defaults: `coupling_dir="Z"`, `field_dir="X"`.

</details>

<details>
<summary><strong>Heisenberg (XXX / XXZ)</strong></summary>

```
H = Jx Σ σˣσˣ + Jy Σ σʸσʸ + Jz Σ σᶻσᶻ + hx Σ σˣ + hy Σ σʸ + hz Σ σᶻ
```

Parameters to provide:
- `N`, `Jx`, `Jy`, `Jz`
- Optional: `hx`, `hy`, `hz` (default to 0)

`Jx=Jy=Jz` → isotropic XXX Heisenberg; `Jx=Jy≠Jz` → XXZ.

</details>

<details>
<summary><strong>Long-Range Ising</strong></summary>

```
H = J Σ_{i<j} σᶻᵢσᶻⱼ / |i-j|^alpha + h Σ σˣᵢ
```

Parameters to provide:
- `N`, `J`, `alpha` (power-law exponent), `h`, `coupling_dir`, `field_dir`

ED uses the exact power-law sum — no approximation needed (unlike the TN version which uses MPO compression).

</details>

> **What about DMRG / TDVP?** Those algorithms handle larger systems (N ~ 100–1000) but require direct Julia usage. The chatbot is intentionally scoped to ED because it fits a short, interactive workflow. See the [ED User Guide](../ED_docs/ED_USER_GUIDE.md) for ED physics background.

---

## Algorithms

**`ed_spectrum`** — Computes energy eigenvalues and eigenstates.
- Use for: ground state energy, energy gaps, phase identification
- `use_sparse`: automatically set to `false` for N ≤ 12, `true` for N = 13–14
- Optional: `n_states` to compute only the lowest N eigenvalues

**`ed_time_evolution`** — Time-evolves an initial state under the Hamiltonian.
- Use for: quench dynamics, magnetization evolution, entanglement growth
- Parameters: `dt` (time step), total time (chatbot computes `n_steps = total_time / dt`)

---

## Initial States

<details>
<summary><strong>Available initial states</strong></summary>

| State | Description |
|-------|-------------|
| `random` | Random normalized state vector |
| `polarized` | All spins aligned in one direction (`spin_direction`: X/Y/Z, `eigenstate`: 1=down, 2=up) |
| `neel` | Alternating ↑↓↑↓ (`even_state` and `odd_state`) |
| `kink` | Domain wall — left half one state, right half another (`position` sets the boundary) |

</details>

For `ed_spectrum`, the initial state affects convergence for iterative methods but the eigenvalues found are exact regardless. For `ed_time_evolution`, the initial state is physically significant — it's the state being evolved.

---

## Config Review Workflow

Once Claude proposes a config, the right panel shows:
- A plain-English **summary** of the simulation
- The full **JSON config** for inspection

**Actions available:**

| Button | Effect |
|--------|--------|
| **Confirm & Run** | Sends config to Julia pipeline and starts polling for status |
| **Edit** | Opens the JSON in an editable textarea — useful for fine-tuning a parameter without restarting the conversation |
| **Save** | Validates and applies manual edits (rejects invalid JSON with an error message) |
| **Discard** | Abandons manual edits and reverts to the last accepted config |
| **Cancel** | Dismisses the config card entirely; prompts you to describe changes in chat |

> **Tip:** Use **Edit** for small numerical tweaks (e.g. changing `J` from `-1` to `-0.5`). For structural changes (different model or algorithm), it's cleaner to tell Claude in chat.

---

## Session Persistence

Your session ID is stored in `localStorage` under the key `tn_ed_session`. This means:
- Refreshing the page resumes the same conversation with Claude (history is preserved server-side)
- Opening a new tab starts a fresh session
- Sessions are in-memory only — they are lost when the chatbot server restarts

---

## Deduplication

The Julia catalog system SHA-hashes every config. If you run an identical simulation twice, the second run returns the cached result immediately (`deduplicated: true`) without recomputing. Claude will note this in its result interpretation.

See [Catalog System Architecture](../Catalog_Query/CATALOG_SYSTEM_ARCHITECTURE.md) for details.
