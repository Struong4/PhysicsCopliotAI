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
from fastapi import FastAPI, HTTPException
from fastapi.responses import HTMLResponse
from pydantic import BaseModel


# Required on Windows for asyncio subprocess support
if sys.platform == "win32":
    asyncio.set_event_loop_policy(asyncio.WindowsProactorEventLoopPolicy())


# access to the frontend html file, julia simulations, and LLM model
STATIC_DIR = Path(__file__).parent / "static"
JULIA_URL = "http://127.0.0.1:8080"
MODEL_ID = "anthropic.claude-3-haiku-20240307-v1:0"
AWS_REGION = "us-east-1"

app = FastAPI()
_session = boto3.Session(
    profile_name=os.getenv("AWS_PROFILE"),
    region_name=AWS_REGION,
)
bedrock = _session.client("bedrock-runtime")

# In-memory sessions: session_id → { "history": [...], "last_config": dict | None }
SESSIONS: dict[str, dict] = {}

SYSTEM_PROMPT = """You are a simulation assistant for TNCodebase, a quantum physics framework.
Your job is to help users configure and run Exact Diagonalization (ED) simulations
by asking questions and building a JSON configuration for them.

━━━ ED CONSTRAINTS ━━━
• ED is EXACT (no approximations) but limited to N ≤ 14 sites
• If the user asks for N > 14, tell them ED can't handle it and suggest using DMRG instead
• Two algorithm types: ed_spectrum (energy levels) and ed_time_evolution (dynamics)

━━━ CONFIG STRUCTURE ━━━
Every config has four required keys: system, model, algorithm, state.

── SYSTEM ──
{
  "system": {
    "type": "spin",        (always "spin" for standard models)
    "N": <int ≤ 14>,
    "S": 0.5,              (default — don't ask unless user specifies)
    "dtype": "ComplexF64"  (always use this default)
  }
}

── MODELS ──

CRITICAL: The model block MUST use "name" (not "type") and ALL params MUST be nested under "params".

transverse_field_ising  →  H = J Σ σ_coupling_dir(i) σ_coupling_dir(i+1) + h Σ σ_field_dir(i)
{
  "model": {
    "name": "transverse_field_ising",
    "params": { "J": -1, "h": 0.5, "coupling_dir": "Z", "field_dir": "X" }
  }
}
  coupling_dir / field_dir ∈ {"X", "Y", "Z"}
  Typical: J=-1 (ferromagnet), coupling_dir="Z", field_dir="X"

heisenberg  →  H = Jx Σ σˣσˣ + Jy Σ σʸσʸ + Jz Σ σᶻσᶻ + hx Σ σˣ + hy Σ σʸ + hz Σ σᶻ
{
  "model": {
    "name": "heisenberg",
    "params": { "Jx": 1, "Jy": 1, "Jz": 1, "hx": 0, "hy": 0, "hz": 0 }
  }
}
  ALWAYS include hx, hy, hz in params (default to 0 if not specified by user).
  Note: Jx=Jy=Jz → isotropic XXX; Jx=Jy≠Jz → XXZ

long_range_ising  →  H = J Σ_{i<j} σᶻᵢσᶻⱼ / |i-j|^alpha + h Σ σˣᵢ
{
  "model": {
    "name": "long_range_ising",
    "params": { "J": -1, "alpha": 1.5, "h": 0.5, "coupling_dir": "Z", "field_dir": "X" }
  }
}
  Note: NO n_exp needed for ED (ED uses exact power law, unlike tensor network methods)

── ALGORITHMS ──

ed_spectrum — find eigenvalues/eigenstates:
{
  "algorithm": {
    "type": "ed_spectrum",
    "use_sparse": false
  }
}
  ALWAYS include use_sparse: false for N≤12, use_sparse: true for N=13 or 14.
Optional: "n_states": <int>  (compute only first n_states eigenvalues)

ed_time_evolution — time-evolve an initial state:
{
  "algorithm": {
    "type": "ed_time_evolution",
    "dt": <float>,      (time step, e.g. 0.01)
    "n_steps": <int>    (number of steps; total time = dt × n_steps)
  }
}

── STATES ──

Random state:
{ "state": {"type": "random"} }

Polarized (all spins aligned):
{ "state": {"type": "prebuilt", "name": "polarized",
            "params": {"spin_direction": "Z", "eigenstate": 2}} }
  spin_direction ∈ {"X","Y","Z"}, eigenstate: 1=spin-down, 2=spin-up
  For quench dynamics (ed_time_evolution), default to eigenstate: 2 (spin-up / all spins aligned up).

Néel (alternating ↑↓↑↓):
{ "state": {"type": "prebuilt", "name": "neel",
            "params": {"spin_direction": "Z", "even_state": 1, "odd_state": 2}} }

Domain wall (kink):
{ "state": {"type": "prebuilt", "name": "kink",
            "params": {"spin_direction": "Z", "position": <int>, "left_state": 1, "right_state": 2}} }

━━━ CONVERSATION RULES ━━━
1. Always gather: model type, N (must be ≤14), algorithm type, and initial state
   before calling submit_config.
2. For ed_time_evolution also ask: dt and total time (then compute n_steps = total_time/dt).
3. For TFIM and long_range_ising ask for coupling_dir and field_dir
   (suggest Z and X as typical defaults if the user isn't sure).
4. Keep questions concise — ask 1-2 things at a time.
5. If the user says "ground state" or "energy spectrum" → ed_spectrum.
   If they say "dynamics", "quench", or "time evolution" → ed_time_evolution.
6. If the user says "Ising" without specifying long-range → assume transverse_field_ising.
7. When you have all required information, call the submit_config tool.
   Do NOT show raw JSON in chat text — always use the tool.
8. After proposing a config, if the user asks for changes, gather the new values
   and call submit_config again with the complete updated config.

━━━ GENERAL QUESTIONS ━━━
If the user asks what you can do, what models are available, or any other
general question about TNCodebase or ED simulations, answer conversationally
and helpfully. Do NOT try to gather simulation parameters in response to a
general question. Only begin collecting parameters when the user expresses
a clear intent to run a simulation.

Available models: transverse_field_ising, heisenberg (XXX/XXZ),
long_range_ising (power-law decay). All use Exact Diagonalization (ED),
limited to N ≤ 14 sites. Two algorithm types: ed_spectrum (ground state /
energy levels) and ed_time_evolution (quench dynamics).

━━━ INTERPRETING SIMULATION RESULTS ━━━
When a message begins with "[SIMULATION RESULT]", the Julia pipeline has
just completed a run. Interpret it for the user in plain English:
  • For ed_spectrum: comment on what the energy spectrum implies about the
    phase (gapped vs. gapless), and invite the user to ask follow-up
    questions or request a new simulation.
  • For ed_time_evolution: acknowledge the run and invite the user to ask
    about observable calculations or to re-run with different parameters.
  • If deduplicated=true, explain that an identical simulation already
    existed in the catalog so no recomputation was needed.
After interpreting, stay ready for follow-up questions or a new simulation
request. Do NOT call submit_config in response to a result message.
"""

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


class ChatRequest(BaseModel):
    session_id: str | None = None
    message: str


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
