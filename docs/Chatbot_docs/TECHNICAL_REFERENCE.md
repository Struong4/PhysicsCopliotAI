# Technical Reference

## Table of Contents
1. [Architecture](#architecture)
2. [API Endpoints](#api-endpoints)
3. [Session Management](#session-management)
4. [Bedrock Integration](#bedrock-integration)
5. [System Prompt & Tool Use](#system-prompt--tool-use)
6. [Config Schema](#config-schema)
7. [Frontend State Machine](#frontend-state-machine)

---

## Architecture

```
Browser (index.html)
    │  POST /api/chat  (user message)
    │  POST /api/run   (confirmed config)
    │  GET  /api/status/{id}
    ▼
FastAPI server (port 8000)        chatbot/app.py
    │  converse(messages, tools)
    ▼
AWS Bedrock — Claude Haiku         us-east-1
    │
    │  (on submit_config tool call)
    │
    │  POST /api/run
    ▼
Julia HTTP server (port 8080)     start_server.jl → pipeline_server.jl
    │
    ▼
TNCodebase Julia pipeline         data/ + data_obs/
```

**Why two servers?**
Julia's startup time (~30–60 s for first load) makes it unsuitable as a web server that's restarted frequently. The Julia server is started once and stays running, while the Python/FastAPI chatbot can be restarted (`--reload`) without affecting ongoing simulations.

---

## API Endpoints

### `GET /`
Serves `chatbot/static/index.html`. No parameters.

---

### `POST /api/chat`

Sends a user message to Bedrock and returns Claude's response.

**Request body:**
```json
{
  "session_id": "string | null",
  "message": "string"
}
```
If `session_id` is null, a new UUID is created and returned.

**Response:**
```json
{
  "session_id": "string",
  "text": "string",
  "config": "object | null",
  "summary": "string"
}
```
`config` is non-null only when Claude invoked the `submit_config` tool (see [System Prompt & Tool Use](#system-prompt--tool-use)).

---

### `POST /api/run`

Forwards a confirmed config to the Julia pipeline server.

**Request body:**
```json
{
  "config": { ... },
  "mode": "simulation"
}
```

**Response:** Proxied from Julia. On success, includes `tracking_id` for polling.

**Timeouts:**
- Connect timeout: immediate (raises 503 if Julia server unreachable)
- Read timeout: 30 seconds (raises 504)

---

### `GET /api/status/{tracking_id}`

Polls the Julia server for the status of a running simulation. Proxied directly; 10-second timeout.

**Response fields from Julia:**
```json
{
  "status": "queued | running | completed | failed",
  "last_message": "string",
  "result": { "run_id": "...", "run_dir": "...", "deduplicated": false }
}
```

---

## Session Management

Sessions are stored in a module-level dict in `app.py`:

```python
SESSIONS: dict[str, dict] = {}
# Structure: { session_id: { "history": [...], "last_config": dict | None } }
```

**History format** follows the Bedrock `converse` API message structure:
```python
[
  {"role": "user",      "content": [{"text": "..."}]},
  {"role": "assistant", "content": [{"text": "..."} | {"toolUse": {...}}]},
  ...
]
```

**Why in-memory?** Simplicity. The chatbot is a development/research tool, not a multi-user production service. A persistent store (Redis, DB) would add operational overhead for no practical gain in this context.

**Tool result injection:** When Claude calls `submit_config`, Bedrock requires the next message in history to be a `toolResult`. The server automatically appends this synthetic user turn, then appends a synthetic assistant acknowledgment, to keep the conversation turn order valid for subsequent API calls.

**Session ID** is stored in the browser's `localStorage` under `tn_ed_session` so it survives page refreshes.

---

## Bedrock Integration

| Setting | Value |
|---------|-------|
| Model | `anthropic.claude-3-haiku-20240307-v1:0` |
| Region | `us-east-1` |
| Max tokens | 2048 |
| Temperature | 0.5 |
| API | `bedrock-runtime.converse()` |

`converse()` is called in a thread (`asyncio.to_thread`) so it doesn't block FastAPI's async event loop.

**Windows compatibility:** `asyncio.WindowsProactorEventLoopPolicy` is set at startup. This is required for asyncio subprocess support on Windows — the default `SelectorEventLoop` doesn't support it.

**AWS credentials** are read by `boto3.Session` from the standard credential chain (`AWS_PROFILE` env var → `~/.aws/credentials` → instance role). The region is hardcoded to `us-east-1` because that is where the Bedrock Claude models are available.

---

## System Prompt & Tool Use

Claude's behavior is controlled by a system prompt defined in `SYSTEM_PROMPT` (`app.py:53`). It specifies:
- ED constraints and what parameters are required for each model
- Conversation rules (ask 1–2 questions at a time, don't show raw JSON in chat)
- How to interpret `[SIMULATION RESULT]` injected messages
- When to call `submit_config` vs. when to answer conversationally

**`submit_config` tool** (`app.py:173`) is the only tool available to Claude. It is defined using Bedrock's `toolSpec` format and contains the full config JSON schema. Claude calls it only when all required fields have been collected.

> **Why a tool instead of asking Claude to output JSON in chat?** Tool use enforces a structured schema — Claude cannot accidentally produce malformed JSON or omit required fields. It also keeps raw JSON out of the chat text, giving the UI a clean separation between conversation and config display.

---

## Config Schema

Every simulation config has four required top-level keys:

```json
{
  "system":    { "type": "spin", "N": <int ≤ 14>, "S": 0.5, "dtype": "ComplexF64" },
  "model":     { "type": "<model_name>", ... model-specific params ... },
  "algorithm": { "type": "ed_spectrum | ed_time_evolution", ... },
  "state":     { "type": "random | prebuilt", ... }
}
```

<details>
<summary><strong>Model parameter details</strong></summary>

**transverse_field_ising**
```json
{ "type": "transverse_field_ising", "N": 10, "J": -1.0, "h": 0.5,
  "coupling_dir": "Z", "field_dir": "X" }
```

**heisenberg**
```json
{ "type": "heisenberg", "N": 10, "Jx": 1.0, "Jy": 1.0, "Jz": 1.0,
  "hx": 0.0, "hy": 0.0, "hz": 0.0 }
```

**long_range_ising**
```json
{ "type": "long_range_ising", "N": 10, "J": -1.0, "alpha": 1.5, "h": 0.3,
  "coupling_dir": "Z", "field_dir": "X" }
```

</details>

<details>
<summary><strong>Algorithm parameter details</strong></summary>

**ed_spectrum**
```json
{ "type": "ed_spectrum", "use_sparse": false }
// use_sparse: false for N ≤ 12, true for N = 13–14
// optional: "n_states": <int>
```

**ed_time_evolution**
```json
{ "type": "ed_time_evolution", "dt": 0.01, "n_steps": 1000 }
```

</details>

The config is SHA-256 hashed by the Julia pipeline for deduplication. See [Catalog System Architecture](../Catalog_Query/CATALOG_SYSTEM_ARCHITECTURE.md).

---

## Frontend State Machine

`index.html` manages UI state in JavaScript without a framework.

**Key state variables:**
```js
sessionId        // string | null — persisted in localStorage
currentConfig    // object | null — config proposed by Claude, awaiting confirmation
lastSubmittedConfig  // object | null — last config sent to /api/run (used for result injection)
pollTimer        // setInterval handle — active while simulation is running
```

**Polling:** After `confirmRun()`, the frontend polls `/api/status/{tracking_id}` every 2 seconds. On `completed`, it calls `injectResultAndChat()` which sends a `[SIMULATION RESULT]` message to `/api/chat` so Claude can interpret the outcome in the conversation.

**Input locking:** The chat input and send button are disabled while Claude is thinking (`setThinking(true)`) and while a simulation is running (re-enabled after result interpretation completes). This prevents out-of-order messages from corrupting session history.
