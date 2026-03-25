"""
TNCodebase ED Simulation Chatbot
FastAPI backend that uses AWS Bedrock (Claude) to build ED simulation configs
from natural language, then submits them to the Julia pipeline server.

Prerequisites:
  - AWS credentials configured (env vars or ~/.aws/credentials)
  - Claude model enabled in Bedrock console (us-east-1)
  - Julia pipeline server running: julia --project=. server/start_server.jl  (port 8080)

Run:
  pip install -r chatbot/requirements.txt
  uvicorn chatbot.app:app --host 127.0.0.1 --port 8000 --reload
  python -m uvicorn chatbot.app:app --host 127.0.0.1 --port 8000 --reload 
  http://localhost:8000
  http://localhost:8080
"""

# libraries needed for connecting this AWS bedrock, HTTP requests, and UI for web
import asyncio
import json
import os
import sys
import uuid
from pathlib import Path

import boto3
import httpx
import yaml
from fastapi import FastAPI, HTTPException
from fastapi.responses import HTMLResponse
from pydantic import BaseModel

from chatbot.registry_loader import load_all as _load_registries
from chatbot.prompt_builder import build_system_prompt

# Path to the simulation run catalog
CATALOG_PATH = Path(__file__).parent.parent / "data" / "run_catalog.jsonl"


def _read_catalog(filters: dict) -> list[dict]:
    """Read and filter run_catalog.jsonl, returning most-recent entries first."""
    if not CATALOG_PATH.exists():
        return []

    algorithm = filters.get("algorithm", "").lower().strip()
    model_name = filters.get("model", "").lower().strip()
    limit = min(int(filters.get("limit", 10)), 50)

    entries = []
    with CATALOG_PATH.open(encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                entry = json.loads(line)
            except json.JSONDecodeError:
                continue
            if algorithm and entry.get("core", {}).get("algorithm", "").lower() != algorithm:
                continue
            if model_name and entry.get("model", {}).get("name", "").lower() != model_name:
                continue
            entries.append(entry)

    entries.reverse()  # most recent first (catalog is append-only)
    return entries[:limit]


async def _read_obs_catalog(filters: dict) -> list[dict]:
    """Query the Julia pipeline server's observable catalog."""
    # limit is not a Julia filter field — apply it in Python after fetching
    limit = filters.get("limit")
    params = {k: v for k, v in filters.items() if v is not None and k in
              ("observable_type", "sim_algorithm", "sim_model_name")}
    try:
        async with httpx.AsyncClient(timeout=10.0) as client:
            r = await client.get(f"{JULIA_URL}/api/query/observables", params=params)
            if r.status_code == 200:
                results = r.json().get("results", [])
                if limit is not None:
                    results = results[:int(limit)]
                return results
    except Exception:
        pass
    return []


# Required on Windows for asyncio subprocess support
if sys.platform == "win32":
    asyncio.set_event_loop_policy(asyncio.WindowsProactorEventLoopPolicy())


# access to the frontend html file, julia simulations, and LLM model
STATIC_DIR = Path(__file__).parent / "static"
JULIA_URL = "http://127.0.0.1:8080"
MODEL_ID = "anthropic.claude-3-haiku-20240307-v1:0"
AWS_REGION = "us-east-1"

# Build system prompt dynamically from registry + keywords (no hardcoded physics knowledge)
_KEYWORDS_PATH = Path(__file__).parent.parent / "mcp_bridge" / "index" / "keywords.yaml"
_registries = _load_registries()
_keywords = yaml.safe_load(_KEYWORDS_PATH.read_text(encoding="utf-8"))

app = FastAPI()
_session = boto3.Session(
    profile_name=os.getenv("AWS_PROFILE") or None,
    region_name=AWS_REGION,
)
bedrock = _session.client("bedrock-runtime")

# In-memory sessions: session_id → { "history": [...], "last_config": dict | None }
SESSIONS: dict[str, dict] = {}

SYSTEM_PROMPT = build_system_prompt(_registries, _keywords)

# gives structure that the json should look like to claude/LLM
# it has instructions to tell claude when to use it and what arguments
# arguments it should pass for a structured result
SUBMIT_CONFIG_TOOL = {
    "name": "submit_config",
    "description": (
        "Call this ONLY when you have gathered all required information and are "
        "ready to propose a complete, valid ED simulation config to the user. "
        "Do not call for partial configs. The config will be shown to the user "
        "for review before running."
    ),
    "inputSchema": {
        "json": {
            "type": "object",
            "properties": {
                "config": {
                    "type": "object",
                    "description": "The complete simulation configuration JSON",
                    "properties": {
                        "system": {"type": "object"},
                        "model": {"type": "object"},
                        "algorithm": {"type": "object"},
                        "state": {"type": "object"},
                        "description": {"type": "string"},
                    },
                    "required": ["system", "model", "algorithm", "state"],
                },
                "summary": {
                    "type": "string",
                    "description": "One plain-English sentence describing what this simulation does",
                },
            },
            "required": ["config", "summary"],
        }
    },
}

QUERY_OBS_CATALOG_TOOL = {
    "name": "query_obs_catalog",
    "description": (
        "Search the observable calculations catalog to find already-computed observables. "
        "Use this when the user wants to plot, view, or retrieve existing observable results "
        "without running a new calculation. Returns obs_run_id entries with metadata."
    ),
    "inputSchema": {
        "json": {
            "type": "object",
            "properties": {
                "observable_type": {
                    "type": "string",
                    "description": "Filter by observable type (e.g. correlation_function, entanglement_entropy). Omit for all.",
                },
                "sim_algorithm": {
                    "type": "string",
                    "description": "Filter by simulation algorithm: dmrg, tdvp, ed_spectrum, ed_time_evolution.",
                },
                "sim_model_name": {
                    "type": "string",
                    "description": "Filter by model name (e.g. heisenberg, transverse_field_ising).",
                },
                "limit": {
                    "type": "integer",
                    "description": "Maximum results to return (default 10, max 50).",
                },
            },
        }
    },
}

SHOW_OBSERVABLE_RESULTS_TOOL = {
    "name": "show_observable_results",
    "description": (
        "Call this after querying the obs catalog to display an existing observable calculation "
        "in the right panel. Use the obs_run_id from query_obs_catalog results."
    ),
    "inputSchema": {
        "json": {
            "type": "object",
            "properties": {
                "obs_run_id": {
                    "type": "string",
                    "description": "The observable run ID to display (from query_obs_catalog results)",
                },
                "summary": {
                    "type": "string",
                    "description": "One sentence describing what is being shown",
                },
            },
            "required": ["obs_run_id", "summary"],
        }
    },
}

CALCULATE_OBSERVABLE_TOOL = {
    "name": "calculate_observable",
    "description": (
        "Call this when the user wants to compute or analyze an observable on a past simulation run. "
        "Use query_catalog first to find the run_id if not already known. "
        "The config will be shown to the user for review before submitting."
    ),
    "inputSchema": {
        "json": {
            "type": "object",
            "properties": {
                "run_id": {
                    "type": "string",
                    "description": "The simulation run_id from the catalog (e.g. 20260220_110253_32cff383)",
                },
                "observable_type": {
                    "type": "string",
                    "description": (
                        "Observable type key. One of: single_site_expectation, expectation_all_sites, "
                        "subsystem_expectation_sum, two_site_expectation, correlation_function, "
                        "connected_correlation, correlation_matrix, entanglement_entropy, "
                        "entanglement_spectrum, energy_expectation, energy_variance, "
                        "boson_number, boson_distribution, boson_field, boson_spin_entanglement"
                    ),
                },
                "params": {
                    "type": "object",
                    "description": (
                        "Observable parameters. Required keys by type: "
                        "single_site_expectation: {site, operator}. "
                        "correlation_function: {site_i, site_j, operator} — SAME operator at both sites (e.g. ZZ, XX). "
                        "connected_correlation: {site_i, site_j, operator} — same as correlation_function but subtracted. "
                        "two_site_expectation: {site_i, site_j, operator_i, operator_j} — DIFFERENT operators at each site (e.g. XZ). "
                        "entanglement_entropy: {bond}. energy_expectation: {}. "
                        "IMPORTANT: use correlation_function (not two_site_expectation) when the user asks for "
                        "spin-spin correlation, ZZ/XX/YY correlation, or any same-operator two-point function. "
                        "Only use two_site_expectation when user explicitly wants two DIFFERENT operators. "
                        "For correlation_function/connected_correlation/two_site_expectation: "
                        "site_i MUST be strictly less than site_j, both between 1 and N."
                    ),
                },
                "selection": {
                    "type": "string",
                    "description": "Which sweeps/steps to process: 'all', 'range', 'specific', 'time_range'. Default: 'all'.",
                },
                "summary": {
                    "type": "string",
                    "description": "One plain-English sentence describing what this observable calculation will compute.",
                },
            },
            "required": ["run_id", "observable_type", "params", "summary"],
        }
    },
}

QUERY_CATALOG_TOOL = {
    "name": "query_catalog",
    "description": (
        "Search the simulation run catalog to answer questions about past runs. "
        "Use this when the user asks about previous simulations, past results, "
        "run history, or whether a particular simulation has been done before. "
        "Returns catalog entries with run_id, timestamp, algorithm, model, N, and results_summary."
    ),
    "inputSchema": {
        "json": {
            "type": "object",
            "properties": {
                "algorithm": {
                    "type": "string",
                    "description": "Filter by algorithm type: dmrg, tdvp, ed_spectrum, or ed_time_evolution. Omit to return all algorithms.",
                },
                "model": {
                    "type": "string",
                    "description": "Filter by model name (e.g. heisenberg, transverse_field_ising). Omit to return all models.",
                },
                "limit": {
                    "type": "integer",
                    "description": "Maximum number of results to return (default 10, max 50).",
                },
            },
        }
    },
}

# ── Request models ────────────────────────────────────────────────────────────
# Pydantic models that does data validation and parsing automatically, and provides type safety

# makes how to parse the POST API call as a chatRequest Object that accesses the data
class ChatRequest(BaseModel):
    session_id: str | None = None
    message: str


# confirm in the frontend helps python recieve runRequest to confirm simulation
class RunRequest(BaseModel):
    config: dict
    mode: str = "simulation"


# ── Routes ────────────────────────────────────────────────────────────────────

# calls on index.html and gets it as a webpage as a UI
@app.get("/")
def index():
    return HTMLResponse((STATIC_DIR / "index.html").read_text(encoding="utf-8"))

# creates convo for this session, appends user msg to LLM's prompt (role, content)
@app.post("/api/chat")
async def chat(req: ChatRequest):
    """Send a user message to Claude and return its response + optional proposed config."""
    sid = req.session_id or str(uuid.uuid4())
    if sid not in SESSIONS:
        SESSIONS[sid] = {"history": [], "last_config": None}
    history = SESSIONS[sid]["history"]

    # Append user turn (Bedrock format)
    history.append({"role": "user", "content": [{"text": req.message}]})

    # Call Bedrock in a thread so we don't block the event loop
    # tells Bedrock what tools are available to LLM
    def _call_bedrock():
        return bedrock.converse(
            modelId=MODEL_ID,
            system=[{"text": SYSTEM_PROMPT}],
            messages=history,
            toolConfig={"tools": [
                {"toolSpec": SUBMIT_CONFIG_TOOL},
                {"toolSpec": QUERY_CATALOG_TOOL},
                {"toolSpec": CALCULATE_OBSERVABLE_TOOL},
                {"toolSpec": QUERY_OBS_CATALOG_TOOL},
                {"toolSpec": SHOW_OBSERVABLE_RESULTS_TOOL},
            ]},
            inferenceConfig={"maxTokens": 2048, "temperature": 0.5},
        )

    try:
        response = await asyncio.to_thread(_call_bedrock)
    except Exception as e:
        raise HTTPException(status_code=502, detail=f"Bedrock error: {e}")

    # Tool execution loop: handle executable tools before final response parsing.
    EXECUTABLE_TOOLS = {"query_catalog", "query_obs_catalog"}
    MAX_TOOL_ROUNDS = 5
    for _ in range(MAX_TOOL_ROUNDS):
        content = response["output"]["message"]["content"]

        exec_tool = next(
            (b["toolUse"] for b in content
             if "toolUse" in b and b["toolUse"]["name"] in EXECUTABLE_TOOLS),
            None,
        )
        if exec_tool is None:
            break

        history.append({"role": "assistant", "content": content})

        if exec_tool["name"] == "query_catalog":
            results = _read_catalog(exec_tool["input"])
            result_text = (
                json.dumps(results, indent=2)
                if results else "No matching runs found in the catalog."
            )
        else:  # query_obs_catalog
            results = await _read_obs_catalog(exec_tool["input"])
            result_text = (
                json.dumps(results, indent=2)
                if results else "No matching observable calculations found in the catalog."
            )

        history.append({
            "role": "user",
            "content": [{"toolResult": {
                "toolUseId": exec_tool["toolUseId"],
                "content": [{"text": result_text}],
            }}],
        })

        try:
            response = await asyncio.to_thread(_call_bedrock)
        except Exception as e:
            raise HTTPException(status_code=502, detail=f"Bedrock error: {e}")

    # Parse final response (may still contain submit_config)
    content = response["output"]["message"]["content"]
    history.append({"role": "assistant", "content": content})

    reply_text = ""
    proposed_config = None
    summary = ""
    obs_config = None
    obs_summary = ""
    show_obs_run_id = None
    show_obs_summary = ""

    # extracts user response if it is text or a config file
    for block in content:
        if "text" in block:
            reply_text += block["text"]
        elif "toolUse" in block and block["toolUse"]["name"] == "show_observable_results":
            tool = block["toolUse"]
            show_obs_run_id = tool["input"].get("obs_run_id")
            show_obs_summary = tool["input"].get("summary", "")
            history.append({
                "role": "user",
                "content": [{"toolResult": {
                    "toolUseId": tool["toolUseId"],
                    "content": [{"text": "Observable results displayed to user."}],
                }}],
            })
            ack = reply_text or f"Showing results for observable run {show_obs_run_id}."
            history.append({"role": "assistant", "content": [{"text": ack}]})
            reply_text = ack
        elif "toolUse" in block and block["toolUse"]["name"] == "calculate_observable":
            tool = block["toolUse"]
            obs_config = {
                "run_id": tool["input"].get("run_id"),
                "observable_type": tool["input"].get("observable_type"),
                "params": tool["input"].get("params", {}),
                "selection": tool["input"].get("selection", "all"),
            }
            obs_summary = tool["input"].get("summary", "")
            history.append({
                "role": "user",
                "content": [{"toolResult": {
                    "toolUseId": tool["toolUseId"],
                    "content": [{"text": "Observable config shown to user for review."}],
                }}],
            })
            ack = (
                reply_text
                or "I've prepared the observable calculation config. "
                   "Review it on the right and click Confirm to calculate, "
                   "or let me know what you'd like to change."
            )
            history.append({"role": "assistant", "content": [{"text": ack}]})
            reply_text = ack
        elif "toolUse" in block and block["toolUse"]["name"] == "submit_config":
            tool = block["toolUse"]
            proposed_config = tool["input"].get("config")
            summary = tool["input"].get("summary", "")

            # the LLM is probabilistic, so basically verification to make sure config is correct
            # Enforce N-in-model-params rules (LLM is unreliable on this)
            if proposed_config:
                algo_type = proposed_config.get("algorithm", {}).get("type", "")
                model_params = proposed_config.get("model", {}).get("params", {})
                if algo_type in ("dmrg", "tdvp"):
                    # TN: inject N from system block into model params
                    system_n = proposed_config.get("system", {}).get("N")
                    if system_n is not None and "model" in proposed_config:
                        proposed_config["model"].setdefault("params", {})["N"] = system_n
                elif algo_type in ("ed_spectrum", "ed_time_evolution"):
                    # ED: remove N from model params if LLM incorrectly added it
                    model_params.pop("N", None)
            SESSIONS[sid]["last_config"] = proposed_config

            # Append tool result so the next user turn stays valid
            # Bedrock requires every toolUse to get a toolResult appended to history
            # or next API call will result in validation errors, so this takes care of it
            history.append({
                "role": "user",
                "content": [{"toolResult": {
                    "toolUseId": tool["toolUseId"],
                    "content": [{"text": "Config shown to user for review."}],
                }}],
            })
            # Synthetic assistant acknowledgment keeps conversation history valid
            # Bedrock expects the next turn to be the model so keep a flowing conversation
            ack = (
                reply_text
                or "I've prepared your simulation config. "
                   "Review it on the right and click Confirm to run, "
                   "or let me know what you'd like to change."
            )
            history.append({"role": "assistant", "content": [{"text": ack}]})
            reply_text = ack

    return {
        "session_id": sid,
        "text": reply_text,
        "config": proposed_config,
        "summary": summary,
        "obs_config": obs_config,
        "obs_summary": obs_summary,
        "show_obs_run_id": show_obs_run_id,
        "show_obs_summary": show_obs_summary,
    }


# when user confirms a run with config, it will send to julia pipeline for simulation
@app.post("/api/run")
async def run_pipeline(req: RunRequest):
    """Forward a confirmed config to the Julia pipeline server."""
    async with httpx.AsyncClient(timeout=30.0) as client:
        try:
            r = await client.post(
                f"{JULIA_URL}/api/run",
                json={"mode": req.mode, "config": req.config},
            )
        except httpx.ConnectError:
            raise HTTPException(
                status_code=503,
                detail="Cannot reach Julia pipeline server at port 8080. "
                       "Make sure it is running: julia --project=. server/start_server.jl",
            )
        except httpx.TimeoutException:
            raise HTTPException(
                status_code=504,
                detail="Julia pipeline server did not respond within 30 seconds.",
            )
        if r.status_code not in (200, 202):
            raise HTTPException(status_code=r.status_code, detail=r.text)
        return r.json()


class ObsRequest(BaseModel):
    run_id: str
    observable_type: str
    params: dict = {}
    selection: str = "all"


@app.post("/api/observables/calculate")
async def start_obs_calculation(req: ObsRequest):
    """Forward an observable calculation request to the Julia pipeline server."""
    # Validate site ordering for two-point observables
    two_point_types = {"correlation_function", "connected_correlation", "two_site_expectation"}
    if req.observable_type in two_point_types:
        site_i = req.params.get("site_i")
        site_j = req.params.get("site_j")
        if site_i is not None and site_j is not None:
            if int(site_i) >= int(site_j):
                raise HTTPException(
                    status_code=422,
                    detail=f"site_i must be strictly less than site_j (got site_i={site_i}, site_j={site_j}).",
                )

    # Validate two_site_expectation has operator_i and operator_j (not just operator)
    if req.observable_type == "two_site_expectation":
        if "operator_i" not in req.params or "operator_j" not in req.params:
            raise HTTPException(
                status_code=422,
                detail=(
                    "two_site_expectation requires 'operator_i' and 'operator_j' params (one for each site). "
                    "If you want the same operator at both sites, use correlation_function with 'operator' instead."
                ),
            )

    payload = {
        "run_id": req.run_id,
        "observable": {"type": req.observable_type, "params": req.params},
        "selection": {"selection": req.selection},
    }
    async with httpx.AsyncClient(timeout=30.0) as client:
        try:
            r = await client.post(f"{JULIA_URL}/api/observables/calculate", json=payload)
        except httpx.ConnectError:
            raise HTTPException(
                status_code=503,
                detail="Cannot reach Julia pipeline server at port 8080. "
                       "Make sure it is running: julia --project=. server/start_server.jl",
            )
        if r.status_code not in (200, 202):
            raise HTTPException(status_code=r.status_code, detail=r.text)
        return r.json()


@app.get("/api/obs_results/{obs_run_id}")
async def get_obs_results(obs_run_id: str):
    """Fetch observable results from the Julia pipeline server."""
    async with httpx.AsyncClient(timeout=15.0) as client:
        try:
            r = await client.get(f"{JULIA_URL}/api/results/observables/{obs_run_id}")
        except httpx.ConnectError:
            raise HTTPException(status_code=503, detail="Julia pipeline server unreachable")
        if r.status_code == 404:
            raise HTTPException(status_code=404, detail="Observable results not found.")
        return r.json()


# checks status of the run to see if the endpoint is done yet
@app.get("/api/status/{tracking_id}")
async def poll_status(tracking_id: str):
    """Proxy a status poll to the Julia pipeline server."""
    async with httpx.AsyncClient(timeout=60.0) as client:
        try:
            r = await client.get(f"{JULIA_URL}/api/status/{tracking_id}")
        except httpx.ConnectError:
            raise HTTPException(status_code=503, detail="Julia pipeline server unreachable")
        return r.json()
