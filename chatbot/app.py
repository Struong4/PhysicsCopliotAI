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
            toolConfig={"tools": [{"toolSpec": SUBMIT_CONFIG_TOOL}]},
            inferenceConfig={"maxTokens": 2048, "temperature": 0.5},
        )

    try:
        response = await asyncio.to_thread(_call_bedrock)
    except Exception as e:
        raise HTTPException(status_code=502, detail=f"Bedrock error: {e}")

    # Parse response
    content = response["output"]["message"]["content"]
    history.append({"role": "assistant", "content": content})

    reply_text = ""
    proposed_config = None
    summary = ""

    # extracts user response if it it text of config file
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
            # Bedrock requiers every toolUse to get a toolResult appended to history
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
