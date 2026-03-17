# Quick Start

## Table of Contents
1. [Prerequisites](#prerequisites)
2. [Install Dependencies](#install-dependencies)
3. [Start the Julia Pipeline Server](#start-the-julia-pipeline-server)
4. [Start the Chatbot](#start-the-chatbot)
5. [First Simulation](#first-simulation)

---

## Prerequisites

**AWS credentials** with Bedrock access:
- Claude Haiku (`anthropic.claude-3-haiku-20240307-v1:0`) must be enabled in the AWS Bedrock console (region `us-east-1`)
- Credentials in `~/.aws/credentials` or as environment variables:
  ```
  AWS_ACCESS_KEY_ID=...
  AWS_SECRET_ACCESS_KEY=...
  AWS_SESSION_TOKEN=...   # if using temporary credentials
  ```
- Optional: set `AWS_PROFILE` to select a named profile

> **Why Bedrock?** The LLM is hosted by AWS rather than run locally — no GPU or local model required. Credentials use standard AWS IAM so there are no API keys in the codebase.

**Julia pipeline server** on port 8080 — see [below](#start-the-julia-pipeline-server).

**Python 3.9+** with pip.

---

## Install Dependencies

```bash
pip install -r chatbot/requirements.txt
```

---

## Start the Julia Pipeline Server

The chatbot forwards confirmed simulation configs here for execution. Start it first:

```bash
julia start_server.jl
```

> **Note:** The first run compiles and loads TNCodebase, which takes ~1–2 minutes. Subsequent starts are faster. Wait for `"HTTP server listening on 127.0.0.1:8080"` before starting the chatbot.

---

## Start the Chatbot

```bash
uvicorn chatbot.app:app --host 127.0.0.1 --port 8000 --reload
```

Open **http://127.0.0.1:8000** in your browser.

---

## First Simulation

1. Type: `"Find the ground state energy of a 10-site Heisenberg chain"`
2. Claude gathers any missing parameters conversationally
3. A simulation config appears in the right panel — review the JSON
4. Click **Confirm & Run** — the config is sent to the Julia server
5. Claude interprets the results when the run completes

See [User Guide](USER_GUIDE.md) for more conversation patterns, model options, and the config review workflow.
