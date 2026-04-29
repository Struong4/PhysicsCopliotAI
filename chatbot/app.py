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

import asyncio
import io
import json
import os
import sys
import threading
import uuid
from collections import defaultdict
from pathlib import Path
from typing import AsyncGenerator

import boto3
from dotenv import load_dotenv
load_dotenv()

import httpx
import numpy as np
import yaml
from fastapi import FastAPI, HTTPException
from fastapi.responses import HTMLResponse, StreamingResponse
from pydantic import BaseModel

from chatbot.registry_loader import load_all as _load_registries
from chatbot.prompt_builder import build_system_prompt
from mcp_bridge.tools.builder import build_config
from chatbot.observable_loader import find_obs_run_dir, load_obs_run, list_obs_runs
from chatbot.tools import TOOL_CONFIG
from chatbot.executors import (
    JULIA_URL,
    _read_catalog,
    _read_obs_catalog,
    _trim_catalog_entry,
    _trim_obs_entry,
    _log_tool_event,
    _user_requested_observable,
    _user_requested_registration,
    _execute_get_simulation_details,
    _execute_get_observable_details,
    _execute_get_run_status,
    _execute_get_available_models,
    _execute_get_available_algorithms,
    _execute_registration,
)

OBS_BASE_DIR = str(Path(__file__).parent.parent / "data_obs")

# Required on Windows for asyncio subprocess support
if sys.platform == "win32":
    asyncio.set_event_loop_policy(asyncio.WindowsProactorEventLoopPolicy())

STATIC_DIR = Path(__file__).parent / "static"
MODEL_ID = "us.anthropic.claude-sonnet-4-6"
AWS_REGION = "us-east-1"

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


def _call_bedrock_stream(history: list, tool_config: dict) -> dict:
    """Calls bedrock.converse_stream(); caller iterates response['stream']."""
    return bedrock.converse_stream(
        modelId=MODEL_ID,
        system=[{"text": SYSTEM_PROMPT}],
        messages=history,
        toolConfig=tool_config,
        inferenceConfig={"maxTokens": 2048, "temperature": 0.5},
    )


def _refresh_system_prompt() -> None:
    """Reload registries and rebuild the system prompt in-memory."""
    global _registries, SYSTEM_PROMPT
    try:
        _registries = _load_registries()
        SYSTEM_PROMPT = build_system_prompt(_registries, _keywords)
    except Exception:
        pass


# ── Request models ────────────────────────────────────────────────────────────

class ChatRequest(BaseModel):
    session_id: str | None = None
    message: str


class RunRequest(BaseModel):
    config: dict
    mode: str = "simulation"


class ObsRequest(BaseModel):
    run_id: str
    observable_type: str
    params: dict = {}
    selection: str = "all"


# ── Routes ────────────────────────────────────────────────────────────────────

@app.get("/")
def index():
    return HTMLResponse((STATIC_DIR / "index.html").read_text(encoding="utf-8"))


async def _stream_chat_response(req: ChatRequest) -> AsyncGenerator[str, None]:
    sid = req.session_id or str(uuid.uuid4())
    if sid not in SESSIONS:
        SESSIONS[sid] = {"history": [], "last_config": None}
    history = SESSIONS[sid]["history"]

    history.append({"role": "user", "content": [{"text": req.message}]})
    yield f"data: {json.dumps({'type': 'session', 'session_id': sid})}\n\n"

    EXECUTABLE_TOOLS = {
        "query_catalog", "query_obs_catalog",
        "register_model", "register_state",
        "get_simulation_details", "get_observable_details", "get_run_status",
        "get_available_models", "get_available_algorithms",
    }
    registered_info = None
    proposed_config = None
    summary = ""
    obs_config = None
    obs_summary = ""
    show_obs_run_id = None
    show_obs_summary = ""
    tracking_id = None
    obs_tracking_id = None
    completed_tool_uses: list = []

    # Single loop: every round uses converse_stream() so the first token arrives
    # immediately without a prior blocking converse() call doubling the latency.
    for _round in range(9):  # max 8 tool rounds + 1 final text round
        try:
            stream_response = await asyncio.to_thread(_call_bedrock_stream, history, TOOL_CONFIG)
        except Exception as e:
            yield f"data: {json.dumps({'type': 'error', 'detail': str(e)})}\n\n"
            return

        full_text = ""
        tool_input_buffers: dict = defaultdict(lambda: {"name": "", "toolUseId": "", "input_str": ""})
        completed_tool_uses = []
        current_block_index: int | None = None
        current_block_is_tool = False

        # Read the boto3 EventStream in a background thread so the async event loop
        # stays free between reads, letting uvicorn flush each SSE frame immediately.
        loop = asyncio.get_event_loop()
        event_queue: asyncio.Queue = asyncio.Queue()

        def _read_stream(sr=stream_response):
            for ev in sr.get("stream", []):
                loop.call_soon_threadsafe(event_queue.put_nowait, ev)
            loop.call_soon_threadsafe(event_queue.put_nowait, None)

        threading.Thread(target=_read_stream, daemon=True).start()

        while True:
            event = await event_queue.get()
            if event is None:
                break

            if "contentBlockStart" in event:
                start = event["contentBlockStart"]
                idx = start.get("contentBlockIndex", 0)
                block = start.get("start", {})
                if "toolUse" in block:
                    current_block_index = idx
                    current_block_is_tool = True
                    tool_input_buffers[idx]["name"] = block["toolUse"].get("name", "")
                    tool_input_buffers[idx]["toolUseId"] = block["toolUse"].get("toolUseId", "")
                else:
                    current_block_is_tool = False

            elif "contentBlockDelta" in event:
                delta = event["contentBlockDelta"].get("delta", {})
                if "text" in delta:
                    chunk = delta["text"]
                    full_text += chunk
                    yield f"data: {json.dumps({'type': 'token', 'text': chunk})}\n\n"
                elif "toolUse" in delta and current_block_index is not None:
                    tool_input_buffers[current_block_index]["input_str"] += delta["toolUse"].get("input", "")

            elif "contentBlockStop" in event:
                if current_block_is_tool and current_block_index is not None:
                    buf = tool_input_buffers[current_block_index]
                    try:
                        parsed_input = json.loads(buf["input_str"]) if buf["input_str"] else {}
                    except json.JSONDecodeError:
                        parsed_input = {}
                    completed_tool_uses.append({
                        "toolUseId": buf["toolUseId"],
                        "name": buf["name"],
                        "input": parsed_input,
                    })
                current_block_is_tool = False
                current_block_index = None

        # Append this round's response to history
        text_blocks = [{"text": full_text}] if full_text else []
        tool_blocks = [{"toolUse": t} for t in completed_tool_uses]
        history.append({"role": "assistant", "content": text_blocks + tool_blocks})

        # Execute executable tools and immediately process non-executable tools from
        # this same round so every tool_use block gets a paired tool_result before
        # any subsequent message is appended.
        exec_tools = [t for t in completed_tool_uses if t["name"] in EXECUTABLE_TOOLS]

        for exec_tool in exec_tools:
            tool_name = exec_tool["name"]
            tool_args = exec_tool["input"]
            _log_tool_event("TOOL_CALL", tool_name, args=tool_args)
            yield f"data: {json.dumps({'type': 'thinking', 'text': f'Using {tool_name}…'})}\n\n"

            if tool_name == "query_catalog":
                raw = _read_catalog(tool_args)
                result_text = json.dumps([_trim_catalog_entry(e) for e in raw], indent=2) if raw else "No matching runs found in the catalog."
                _log_tool_event("TOOL_RESULT", tool_name, result_summary=f"count={len(raw)}")
            elif tool_name == "query_obs_catalog":
                raw = await _read_obs_catalog(tool_args)
                result_text = json.dumps([_trim_obs_entry(e) for e in raw], indent=2) if raw else "No matching observable calculations found in the catalog."
                _log_tool_event("TOOL_RESULT", tool_name, result_summary=f"count={len(raw)}")
            elif tool_name == "get_simulation_details":
                result_text = await _execute_get_simulation_details(tool_args.get("run_id", ""))
                _log_tool_event("TOOL_RESULT", tool_name, result_summary=f"run_id={tool_args.get('run_id')}")
            elif tool_name == "get_observable_details":
                result_text = await _execute_get_observable_details(tool_args.get("obs_run_id", ""))
                _log_tool_event("TOOL_RESULT", tool_name, result_summary=f"obs_run_id={tool_args.get('obs_run_id')}")
            elif tool_name == "get_run_status":
                result_text = await _execute_get_run_status(tool_args.get("tracking_id", ""))
                _log_tool_event("TOOL_RESULT", tool_name, result_summary=f"tracking_id={tool_args.get('tracking_id')}")
            elif tool_name == "get_available_models":
                result_text = _execute_get_available_models(_registries, tool_args.get("system_type"))
                _log_tool_event("TOOL_RESULT", tool_name, result_summary="models listed")
            elif tool_name == "get_available_algorithms":
                result_text = _execute_get_available_algorithms(_registries)
                _log_tool_event("TOOL_RESULT", tool_name, result_summary="algorithms listed")
            else:  # register_model or register_state
                if not _user_requested_registration(req.message, history):
                    result_text = "No explicit registration request detected; call ignored."
                    _log_tool_event("TOOL_SKIP", tool_name, result_summary="no registration intent")
                else:
                    result_text = await _execute_registration(tool_name, tool_args, on_success=_refresh_system_prompt)
                    if not result_text.startswith("Registration failed") and not result_text.startswith("Cannot reach"):
                        registered_info = {
                            "type": "model" if tool_name == "register_model" else "state",
                            "name": tool_args.get("name"),
                            "display_name": tool_args.get("display_name"),
                            "system_type": tool_args.get("system_type"),
                            "backend": tool_args.get("backend"),
                        }
                    _log_tool_event("TOOL_RESULT", tool_name, result_summary=result_text[:80])

            history.append({
                "role": "user",
                "content": [{"toolResult": {"toolUseId": exec_tool["toolUseId"], "content": [{"text": result_text}]}}],
            })

        # Process non-executable tools from this same round immediately so that
        # no tool_use block is left without a tool_result before the next append.
        for tool in completed_tool_uses:
            if tool["name"] in EXECUTABLE_TOOLS:
                continue
            tool_name = tool["name"]
            tool_input = tool["input"]

            if tool_name == "show_observable_results":
                if _user_requested_observable(req.message):
                    show_obs_run_id = tool_input.get("obs_run_id")
                    show_obs_summary = tool_input.get("summary", "")
                    result_text = "Observable results displayed to user."
                else:
                    result_text = "No observable request detected; call ignored."

            elif tool_name == "calculate_observable":
                obs_auto_run = tool_input.get("auto_run", False)
                if _user_requested_observable(req.message) or obs_auto_run:
                    obs_config = {
                        "run_id": tool_input.get("run_id"),
                        "observable_type": tool_input.get("observable_type"),
                        "params": tool_input.get("params", {}),
                        "selection": tool_input.get("selection", "all"),
                    }
                    obs_summary = tool_input.get("summary", "")
                    if obs_auto_run:
                        try:
                            julia_payload = {"run_id": obs_config["run_id"], "observable": {"type": obs_config["observable_type"], "params": obs_config["params"]}, "selection": {"selection": obs_config["selection"]}}
                            async with httpx.AsyncClient(timeout=60.0) as client:
                                r = await client.post(f"{JULIA_URL}/api/observables/calculate", json=julia_payload)
                            if r.status_code in (200, 202):
                                obs_tracking_id = r.json().get("tracking_id")
                                obs_config = None
                        except (httpx.ConnectError, httpx.ReadTimeout):
                            obs_tracking_id = None
                    result_text = "Observable calculation started." if obs_tracking_id else "Observable config shown to user for review."
                else:
                    result_text = "No observable request detected; call ignored."

            elif tool_name == "submit_config":
                summary = tool_input.get("summary", "")
                try:
                    proposed_config = build_config(
                        _registries,
                        system=tool_input.get("system", {}),
                        model=tool_input.get("model", {}),
                        algorithm=tool_input.get("algorithm", {}),
                        state=tool_input.get("state"),
                        description=summary,
                    )
                except Exception as exc:
                    proposed_config = None
                    print(f"[build_config error] {exc}", flush=True)
                SESSIONS[sid]["last_config"] = proposed_config
                auto_run = tool_input.get("auto_run", False)
                if auto_run and proposed_config:
                    try:
                        async with httpx.AsyncClient(timeout=60.0) as client:
                            r = await client.post(f"{JULIA_URL}/api/run", json={"config": proposed_config, "mode": "simulation"})
                        if r.status_code in (200, 202):
                            tracking_id = r.json().get("tracking_id")
                            proposed_config = None
                    except (httpx.ConnectError, httpx.ReadTimeout):
                        pass
                result_text = "Simulation started." if tracking_id else "Config shown to user for review."

            else:
                result_text = f"Tool {tool_name} acknowledged."

            history.append({
                "role": "user",
                "content": [{"toolResult": {"toolUseId": tool["toolUseId"], "content": [{"text": result_text}]}}],
            })

        if not exec_tools:
            break  # No more executable tools; all non-exec tools handled above

    yield f"data: {json.dumps({'type': 'done', 'session_id': sid, 'config': proposed_config, 'summary': summary, 'tracking_id': tracking_id, 'obs_config': obs_config, 'obs_summary': obs_summary, 'obs_tracking_id': obs_tracking_id, 'show_obs_run_id': show_obs_run_id, 'show_obs_summary': show_obs_summary, 'registered': registered_info})}\n\n"


@app.post("/api/chat/stream")
async def chat_stream(req: ChatRequest):
    return StreamingResponse(
        _stream_chat_response(req),
        media_type="text/event-stream",
        headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"},
    )


@app.post("/api/chat")
async def chat(req: ChatRequest):
    """Send a user message to Claude and return its response + optional proposed config."""
    sid = req.session_id or str(uuid.uuid4())
    if sid not in SESSIONS:
        SESSIONS[sid] = {"history": [], "last_config": None}
    history = SESSIONS[sid]["history"]

    history.append({"role": "user", "content": [{"text": req.message}]})

    def _call_bedrock():
        return bedrock.converse(
            modelId=MODEL_ID,
            system=[{"text": SYSTEM_PROMPT}],
            messages=history,
            toolConfig=TOOL_CONFIG,
            inferenceConfig={"maxTokens": 2048, "temperature": 0.5},
        )

    try:
        response = await asyncio.to_thread(_call_bedrock)
    except Exception as e:
        raise HTTPException(status_code=502, detail=f"Bedrock error: {e}")

    EXECUTABLE_TOOLS = {
        "query_catalog", "query_obs_catalog",
        "register_model", "register_state",
        "get_simulation_details", "get_observable_details", "get_run_status",
        "get_available_models", "get_available_algorithms",
    }
    MAX_TOOL_ROUNDS = 8
    registered_info = None
    for _ in range(MAX_TOOL_ROUNDS):
        content = response["output"]["message"]["content"]

        exec_tools_in_round = [
            b["toolUse"] for b in content
            if "toolUse" in b and b["toolUse"]["name"] in EXECUTABLE_TOOLS
        ]
        if not exec_tools_in_round:
            break

        history.append({"role": "assistant", "content": content})

        for exec_tool in exec_tools_in_round:
            tool_name = exec_tool["name"]
            tool_args = exec_tool["input"]
            _log_tool_event("TOOL_CALL", tool_name, args=tool_args)

            if tool_name == "query_catalog":
                raw = _read_catalog(tool_args)
                if raw:
                    trimmed = [_trim_catalog_entry(e) for e in raw]
                    result_text = json.dumps(trimmed, indent=2)
                    _log_tool_event("TOOL_RESULT", tool_name, result_summary=f"count={len(trimmed)}")
                else:
                    result_text = "No matching runs found in the catalog."
                    _log_tool_event("TOOL_RESULT", tool_name, result_summary="count=0")

            elif tool_name == "query_obs_catalog":
                raw = await _read_obs_catalog(tool_args)
                if raw:
                    trimmed = [_trim_obs_entry(e) for e in raw]
                    result_text = json.dumps(trimmed, indent=2)
                    _log_tool_event("TOOL_RESULT", tool_name, result_summary=f"count={len(trimmed)}")
                else:
                    result_text = "No matching observable calculations found in the catalog."
                    _log_tool_event("TOOL_RESULT", tool_name, result_summary="count=0")

            elif tool_name == "get_simulation_details":
                result_text = await _execute_get_simulation_details(tool_args.get("run_id", ""))
                _log_tool_event("TOOL_RESULT", tool_name, result_summary=f"run_id={tool_args.get('run_id')}")

            elif tool_name == "get_observable_details":
                result_text = await _execute_get_observable_details(tool_args.get("obs_run_id", ""))
                _log_tool_event("TOOL_RESULT", tool_name, result_summary=f"obs_run_id={tool_args.get('obs_run_id')}")

            elif tool_name == "get_run_status":
                result_text = await _execute_get_run_status(tool_args.get("tracking_id", ""))
                _log_tool_event("TOOL_RESULT", tool_name, result_summary=f"tracking_id={tool_args.get('tracking_id')}")

            elif tool_name == "get_available_models":
                result_text = _execute_get_available_models(_registries, tool_args.get("system_type"))
                _log_tool_event("TOOL_RESULT", tool_name, result_summary="models listed")

            elif tool_name == "get_available_algorithms":
                result_text = _execute_get_available_algorithms(_registries)
                _log_tool_event("TOOL_RESULT", tool_name, result_summary="algorithms listed")

            else:  # register_model or register_state
                if not _user_requested_registration(req.message, history):
                    result_text = "No explicit registration request detected; call ignored."
                    _log_tool_event("TOOL_SKIP", tool_name, result_summary="no registration intent")
                else:
                    result_text = await _execute_registration(tool_name, tool_args, on_success=_refresh_system_prompt)
                    if not result_text.startswith("Registration failed") and not result_text.startswith("Cannot reach"):
                        registered_info = {
                            "type": "model" if tool_name == "register_model" else "state",
                            "name": tool_args.get("name"),
                            "display_name": tool_args.get("display_name"),
                            "system_type": tool_args.get("system_type"),
                            "backend": tool_args.get("backend"),
                        }
                    _log_tool_event("TOOL_RESULT", tool_name, result_summary=result_text[:80])

            history.append({
                "role": "user",
                "content": [{"toolResult": {
                    "toolUseId": exec_tool["toolUseId"],
                    "content": [{"text": result_text}],
                }}],
            })

        # Append tool_results for any non-executable tools in this intermediate round
        # to prevent orphaned tool_use blocks when mixed with executable tools.
        for block in content:
            if "toolUse" not in block or block["toolUse"]["name"] in EXECUTABLE_TOOLS:
                continue
            tool = block["toolUse"]
            tool_name = tool["name"]
            tool_input = tool["input"]
            if tool_name == "show_observable_results":
                result_text = "Observable results queued for display." if _user_requested_observable(req.message) else "No observable request detected; call ignored."
            elif tool_name == "calculate_observable":
                result_text = "Observable config queued for review." if (_user_requested_observable(req.message) or tool_input.get("auto_run", False)) else "No observable request detected; call ignored."
            elif tool_name == "submit_config":
                result_text = "Config queued for review."
            else:
                result_text = f"Tool {tool_name} acknowledged."
            history.append({
                "role": "user",
                "content": [{"toolResult": {
                    "toolUseId": tool["toolUseId"],
                    "content": [{"text": result_text}],
                }}],
            })

        try:
            response = await asyncio.to_thread(_call_bedrock)
        except Exception as e:
            raise HTTPException(status_code=502, detail=f"Bedrock error: {e}")

    # Parse final response (may still contain submit_config / observable tools)
    content = response["output"]["message"]["content"]
    history.append({"role": "assistant", "content": content})

    reply_text = ""
    proposed_config = None
    summary = ""
    obs_config = None
    obs_summary = ""
    show_obs_run_id = None
    show_obs_summary = ""
    tracking_id = None
    obs_tracking_id = None

    for block in content:
        if "text" in block:
            reply_text += block["text"]
        elif "toolUse" in block and block["toolUse"]["name"] == "show_observable_results":
            tool = block["toolUse"]
            if _user_requested_observable(req.message):
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
            else:
                history.append({
                    "role": "user",
                    "content": [{"toolResult": {
                        "toolUseId": tool["toolUseId"],
                        "content": [{"text": "No observable request detected; call ignored."}],
                    }}],
                })
        elif "toolUse" in block and block["toolUse"]["name"] == "calculate_observable":
            tool = block["toolUse"]
            obs_auto_run_check = tool["input"].get("auto_run", False)
            if _user_requested_observable(req.message) or obs_auto_run_check:
                obs_config = {
                    "run_id": tool["input"].get("run_id"),
                    "observable_type": tool["input"].get("observable_type"),
                    "params": tool["input"].get("params", {}),
                    "selection": tool["input"].get("selection", "all"),
                }
                obs_summary = tool["input"].get("summary", "")

                obs_auto_run = obs_auto_run_check
                if obs_auto_run:
                    try:
                        julia_payload = {
                            "run_id": obs_config["run_id"],
                            "observable": {
                                "type": obs_config["observable_type"],
                                "params": obs_config["params"],
                            },
                            "selection": {"selection": obs_config["selection"]},
                        }
                        async with httpx.AsyncClient(timeout=60.0) as client:
                            r = await client.post(
                                f"{JULIA_URL}/api/observables/calculate",
                                json=julia_payload,
                            )
                        if r.status_code in (200, 202):
                            obs_tracking_id = r.json().get("tracking_id")
                    except (httpx.ConnectError, httpx.ReadTimeout):
                        obs_tracking_id = None

                tool_result_text = "Observable calculation started." if (obs_auto_run and obs_tracking_id) else "Observable config shown to user for review."
                history.append({
                    "role": "user",
                    "content": [{"toolResult": {
                        "toolUseId": tool["toolUseId"],
                        "content": [{"text": tool_result_text}],
                    }}],
                })
                if obs_auto_run and obs_tracking_id:
                    ack = reply_text or f"Calculating now — {obs_summary}"
                    obs_config = None
                else:
                    ack = (
                        reply_text
                        or "I've prepared the observable calculation config. "
                           "Review it on the right and click Confirm to calculate, "
                           "or let me know what you'd like to change."
                    )
                history.append({"role": "assistant", "content": [{"text": ack}]})
                reply_text = ack
            else:
                history.append({
                    "role": "user",
                    "content": [{"toolResult": {
                        "toolUseId": tool["toolUseId"],
                        "content": [{"text": "No observable request detected; call ignored."}],
                    }}],
                })
        elif "toolUse" in block and block["toolUse"]["name"] == "submit_config":
            tool = block["toolUse"]
            summary = tool["input"].get("summary", "")
            try:
                proposed_config = build_config(
                    _registries,
                    system=tool["input"].get("system", {}),
                    model=tool["input"].get("model", {}),
                    algorithm=tool["input"].get("algorithm", {}),
                    state=tool["input"].get("state"),
                    description=summary,
                )
            except Exception as exc:
                proposed_config = None
                print(f"[build_config error] {exc}", flush=True)
            SESSIONS[sid]["last_config"] = proposed_config

            auto_run = tool["input"].get("auto_run", False)
            tracking_id = None

            if auto_run and proposed_config:
                try:
                    async with httpx.AsyncClient(timeout=60.0) as client:
                        r = await client.post(
                            f"{JULIA_URL}/api/run",
                            json={"config": proposed_config, "mode": "simulation"},
                        )
                    if r.status_code in (200, 202):
                        tracking_id = r.json().get("tracking_id")
                except (httpx.ConnectError, httpx.ReadTimeout):
                    pass

            tool_result_text = "Simulation started." if tracking_id else "Config shown to user for review."
            history.append({
                "role": "user",
                "content": [{"toolResult": {
                    "toolUseId": tool["toolUseId"],
                    "content": [{"text": tool_result_text}],
                }}],
            })
            if tracking_id:
                ack = reply_text or f"Running now — {summary}"
            elif auto_run:
                ack = (
                    reply_text
                    or "Julia took a moment to respond, so the config is ready for you to confirm manually. "
                       "Click Confirm & Run on the right when ready."
                )
            else:
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
        "config": proposed_config if not tracking_id else None,
        "summary": summary,
        "tracking_id": tracking_id,
        "obs_config": obs_config,
        "obs_summary": obs_summary,
        "obs_tracking_id": obs_tracking_id,
        "show_obs_run_id": show_obs_run_id,
        "show_obs_summary": show_obs_summary,
        "registered": registered_info,
    }


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


@app.post("/api/observables/calculate")
async def start_obs_calculation(req: ObsRequest):
    """Forward an observable calculation request to the Julia pipeline server."""
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


@app.delete("/api/registry/models/{name}")
async def delete_registry_model(name: str):
    """Proxy a model deletion to the Julia pipeline server."""
    async with httpx.AsyncClient(timeout=10.0) as client:
        try:
            r = await client.delete(f"{JULIA_URL}/api/registry/models/{name}")
        except httpx.ConnectError:
            raise HTTPException(status_code=503, detail="Julia pipeline server unreachable")
        if r.status_code not in (200, 204):
            raise HTTPException(status_code=r.status_code, detail=r.text)
        _refresh_system_prompt()
        return r.json()


@app.delete("/api/registry/states/{name}")
async def delete_registry_state(name: str):
    """Proxy a state deletion to the Julia pipeline server."""
    async with httpx.AsyncClient(timeout=10.0) as client:
        try:
            r = await client.delete(f"{JULIA_URL}/api/registry/states/{name}")
        except httpx.ConnectError:
            raise HTTPException(status_code=503, detail="Julia pipeline server unreachable")
        if r.status_code not in (200, 204):
            raise HTTPException(status_code=r.status_code, detail=r.text)
        _refresh_system_prompt()
        return r.json()


@app.get("/api/obs_results/{obs_run_id}")
async def get_obs_results(obs_run_id: str):
    """Fetch observable results: tries Julia server first, falls back to local disk loader."""
    try:
        async with httpx.AsyncClient(timeout=15.0) as client:
            r = await client.get(f"{JULIA_URL}/api/results/observables/{obs_run_id}")
            if r.status_code == 200:
                return r.json()
            if r.status_code == 404:
                raise HTTPException(status_code=404, detail="Observable results not found.")
    except httpx.ConnectError:
        pass
    except HTTPException:
        raise
    except Exception:
        pass

    try:
        obs_run_dir = find_obs_run_dir(OBS_BASE_DIR, obs_run_id)
    except FileNotFoundError as exc:
        raise HTTPException(status_code=404, detail=str(exc))

    result = await asyncio.to_thread(load_obs_run, obs_run_dir)
    return result


@app.get("/api/local/obs_data/{obs_run_id}")
async def get_local_obs_data(obs_run_id: str):
    """Read observable results directly from disk (no Julia dependency)."""
    try:
        obs_run_dir = find_obs_run_dir(OBS_BASE_DIR, obs_run_id)
    except FileNotFoundError as exc:
        raise HTTPException(status_code=404, detail=str(exc))

    result = await asyncio.to_thread(load_obs_run, obs_run_dir)
    return result


@app.get("/api/obs_results/{obs_run_id}/numpy")
async def download_obs_numpy(obs_run_id: str):
    """Return sweep numerical data as a compressed .npz file."""
    try:
        obs_run_dir = find_obs_run_dir(OBS_BASE_DIR, obs_run_id)
    except FileNotFoundError as exc:
        raise HTTPException(status_code=404, detail=str(exc))

    result = await asyncio.to_thread(load_obs_run, obs_run_dir)
    data = result.get("data", {})

    arrays = {}
    for key in ("indices", "energies", "bond_dims", "times"):
        if data.get(key):
            arrays[key] = np.array(data[key])

    if data.get("values"):
        try:
            arrays["values"] = np.array(data["values"])
        except ValueError:
            arrays["values"] = np.array(data["values"], dtype=object)

    buf = io.BytesIO()
    np.savez_compressed(buf, **arrays)
    buf.seek(0)

    return StreamingResponse(
        buf,
        media_type="application/octet-stream",
        headers={"Content-Disposition": f'attachment; filename="{obs_run_id}.npz"'},
    )


@app.get("/api/status/{tracking_id}")
async def poll_status(tracking_id: str):
    """Proxy a status poll to the Julia pipeline server."""
    async with httpx.AsyncClient(timeout=120.0) as client:
        try:
            r = await client.get(f"{JULIA_URL}/api/status/{tracking_id}")
        except httpx.ConnectError:
            raise HTTPException(status_code=503, detail="Julia pipeline server unreachable")
        except httpx.ReadTimeout:
            return {"status": "running", "tracking_id": tracking_id, "message": "Server busy; simulation still in progress."}
        return r.json()
