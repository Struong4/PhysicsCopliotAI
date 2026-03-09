"""
TNCodebase ED Simulation Chatbot
FastAPI backend that uses AWS Bedrock (Claude) to build ED simulation configs
from natural language, then submits them to the Julia pipeline server.

Prerequisites:
  - AWS credentials configured (env vars or ~/.aws/credentials)
  - Claude model enabled in Bedrock console (us-east-1)
  - Julia pipeline server running: julia --project=. start_server.jl  (port 8080)

Run:
  pip install -r chatbot/requirements.txt
  uvicorn chatbot.app:app --host 127.0.0.1 --port 8000 --reload
  python -m uvicorn chatbot.app:app --host 127.0.0.1 --port 8000 --reload 
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


# Required on Windows for asyncio subprocess support
if sys.platform == "win32":
    asyncio.set_event_loop_policy(asyncio.WindowsProactorEventLoopPolicy())


# access to the frontend html file, julia simulations, and LLM model
STATIC_DIR = Path(__file__).parent / "static"
JULIA_URL = "http://127.0.0.1:8080"
MODEL_ID = "anthropic.claude-3-haiku-20240307-v1:0"
AWS_REGION = "us-east-1"

# Build system prompt dynamically from registry + keywords (no hardcoded physics knowledge)
_KEYWORDS_PATH = Path(__file__).parent / "keywords.yaml"
_registries = _load_registries()
_keywords = yaml.safe_load(_KEYWORDS_PATH.read_text(encoding="utf-8"))

app = FastAPI()
_session = boto3.Session(
    profile_name=os.getenv("AWS_PROFILE"),
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
            ]},
            inferenceConfig={"maxTokens": 2048, "temperature": 0.5},
        )

    try:
        response = await asyncio.to_thread(_call_bedrock)
    except Exception as e:
        raise HTTPException(status_code=502, detail=f"Bedrock error: {e}")

    # Tool execution loop: handle query_catalog calls (real tool execution)
    # before falling through to the final response parsing.
    MAX_TOOL_ROUNDS = 5
    for _ in range(MAX_TOOL_ROUNDS):
        content = response["output"]["message"]["content"]

        # Find a query_catalog tool use in this response
        catalog_tool = next(
            (b["toolUse"] for b in content
             if "toolUse" in b and b["toolUse"]["name"] == "query_catalog"),
            None,
        )
        if catalog_tool is None:
            break  # no catalog query — proceed to final response handling

        # Append the assistant turn that contains the tool call
        history.append({"role": "assistant", "content": content})

        # Execute the catalog query
        results = _read_catalog(catalog_tool["input"])
        result_text = (
            json.dumps(results, indent=2)
            if results
            else "No matching runs found in the catalog."
        )

        # Return the tool result to the model
        history.append({
            "role": "user",
            "content": [{"toolResult": {
                "toolUseId": catalog_tool["toolUseId"],
                "content": [{"text": result_text}],
            }}],
        })

        # Call Bedrock again with the tool result in history
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

    # extracts user response if it is text or a config file
    for block in content:
        if "text" in block:
            reply_text += block["text"]
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
                       "Make sure it is running: julia --project=. start_server.jl",
            )
        except httpx.TimeoutException:
            raise HTTPException(
                status_code=504,
                detail="Julia pipeline server did not respond within 30 seconds.",
            )
        if r.status_code not in (200, 202):
            raise HTTPException(status_code=r.status_code, detail=r.text)
        return r.json()


# checks status of the run to see if the endpoint is done yet
@app.get("/api/status/{tracking_id}")
async def poll_status(tracking_id: str):
    """Proxy a status poll to the Julia pipeline server."""
    async with httpx.AsyncClient(timeout=10.0) as client:
        try:
            r = await client.get(f"{JULIA_URL}/api/status/{tracking_id}")
        except httpx.ConnectError:
            raise HTTPException(status_code=503, detail="Julia pipeline server unreachable")
        return r.json()
