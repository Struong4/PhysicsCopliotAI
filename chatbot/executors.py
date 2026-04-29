"""
Tool executor functions and catalog helpers for the chatbot.

All functions that handle tool results (reading the catalog, calling Julia
endpoints, querying registries) live here, keeping app.py focused on
routing and the Bedrock conversation loop.
"""

import datetime
import json
import os
from pathlib import Path

import httpx

JULIA_URL = os.environ.get("JULIA_URL", "http://127.0.0.1:8080")
CATALOG_PATH = Path(__file__).parent.parent / "data" / "run_catalog.jsonl"
OBS_CATALOG_PATH = Path(__file__).parent.parent / "data_obs" / "observables_catalog.jsonl"


# ── Catalog helpers ───────────────────────────────────────────────────────────

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

    entries.reverse()
    return entries[:limit]


async def _read_obs_catalog(filters: dict) -> list[dict]:
    """Query observable catalog: tries Julia server first, falls back to local file."""
    limit = filters.get("limit")
    params = {k: v for k, v in filters.items() if v is not None and k in
              ("observable_type", "sim_algorithm", "sim_model_name")}
    url = f"{JULIA_URL}/api/query/observables"
    try:
        async with httpx.AsyncClient(timeout=10.0) as client:
            r = await client.get(url, params=params)
            print(f"[OBS_CATALOG] GET {url} params={params} → {r.status_code}", flush=True)
            if r.status_code == 200:
                results = r.json().get("results", [])
                print(f"[OBS_CATALOG] Julia returned {len(results)} entries", flush=True)
                if results:
                    if limit is not None:
                        results = results[:int(limit)]
                    return results
    except Exception as exc:
        print(f"[OBS_CATALOG] Julia query failed: {exc}", flush=True)

    # Local file fallback: read data_obs/observables_catalog.jsonl directly
    if OBS_CATALOG_PATH.exists():
        print(f"[OBS_CATALOG] Falling back to local {OBS_CATALOG_PATH}", flush=True)
        obs_type_filter = params.get("observable_type", "").lower().strip()
        alg_filter = params.get("sim_algorithm", "").lower().strip()
        model_filter = params.get("sim_model_name", "").lower().strip()
        _limit = min(int(limit), 50) if limit is not None else 10
        entries = []
        with OBS_CATALOG_PATH.open(encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    entry = json.loads(line)
                except json.JSONDecodeError:
                    continue
                if obs_type_filter and entry.get("observable", {}).get("type", "").lower() != obs_type_filter:
                    continue
                if alg_filter and entry.get("simulation", {}).get("core", {}).get("algorithm", "").lower() != alg_filter:
                    continue
                if model_filter and entry.get("simulation", {}).get("model", {}).get("name", "").lower() != model_filter:
                    continue
                entries.append(entry)
        entries.reverse()
        result = entries[:_limit]
        print(f"[OBS_CATALOG] Local fallback found {len(result)} entries", flush=True)
        return result

    print(f"[OBS_CATALOG] No local catalog at {OBS_CATALOG_PATH}", flush=True)
    return []


def _trim_catalog_entry(entry: dict) -> dict:
    """Return a concise summary of a simulation catalog entry for LLM context."""
    core = entry.get("core", {})
    model = entry.get("model", {})
    results = entry.get("results_summary", {})
    return {
        "run_id": entry.get("run_id"),
        "timestamp": entry.get("timestamp"),
        "status": entry.get("status"),
        "algorithm": core.get("algorithm"),
        "N": core.get("N") or core.get("N_spins"),
        "model_name": model.get("name"),
        "model_params": model.get("params", {}),
        "final_energy": results.get("final_energy") or results.get("ground_energy"),
        "sweeps_completed": results.get("sweeps_completed"),
    }


def _trim_obs_entry(entry: dict) -> dict:
    """Return a concise summary of an observable catalog entry for LLM context."""
    sim = entry.get("simulation", {})
    obs = entry.get("observable", {})
    results = entry.get("results_summary", {})
    sim_core = sim.get("core", {})
    sim_model = sim.get("model", {})
    return {
        "obs_run_id": entry.get("obs_run_id"),
        "sim_run_id": entry.get("sim_run_id"),
        "timestamp": entry.get("timestamp"),
        "status": entry.get("status"),
        "observable_type": obs.get("type"),
        "observable_params": obs.get("params", {}),
        "sim_algorithm": sim_core.get("algorithm"),
        "sim_N": sim_core.get("N") or sim_core.get("N_spins"),
        "sim_model_name": sim_model.get("name"),
        "n_analyzed": (
            results.get("n_sweeps_analyzed")
            or results.get("n_steps_analyzed")
            or results.get("n_states_analyzed")
        ),
    }


# ── Logging ───────────────────────────────────────────────────────────────────

def _log_tool_event(
    event_type: str,
    tool_name: str,
    args: dict | None = None,
    result_summary: str | None = None,
) -> None:
    ts = datetime.datetime.now().strftime("%H:%M:%S")
    if event_type == "TOOL_CALL":
        args_str = f" args={json.dumps(args)}" if args else ""
        print(f"[{ts}] [TOOL_CALL] {tool_name}{args_str}", flush=True)
    elif event_type == "TOOL_RESULT":
        summary_str = f" {result_summary}" if result_summary else ""
        print(f"[{ts}] [TOOL_RESULT] {tool_name}{summary_str}", flush=True)
    elif event_type == "TOOL_ERROR":
        print(f"[{ts}] [TOOL_ERROR] {tool_name}: {result_summary}", flush=True)
    elif event_type == "TOOL_SKIP":
        print(f"[{ts}] [TOOL_SKIP] {tool_name}: {result_summary}", flush=True)


# ── Intent guards ─────────────────────────────────────────────────────────────

_OBSERVABLE_TRIGGER_WORDS = {
    "plot", "show", "display", "view", "visualize",
    "observable", "observation",
    "entanglement", "magnetization", "correlation", "entropy",
    "expectation", "expectation value", "energy variance", "boson number", "boson distribution",
    "boson field", "spin entanglement", "correlation matrix", "correlation function",
    "single site", "all sites", "subsystem",
}

def _user_requested_observable(message: str) -> bool:
    msg = message.lower()
    return any(w in msg for w in _OBSERVABLE_TRIGGER_WORDS)


_REGISTRY_TRIGGER_WORDS = {
    "register", "register model", "register state",
    "add a model", "add a state", "add model", "add state",
    "save a model", "save a state", "new user model", "new user state",
}

def _user_requested_registration(message: str, history: list | None = None) -> bool:
    if any(w in message.lower() for w in _REGISTRY_TRIGGER_WORDS):
        return True
    if history:
        for turn in history[-20:]:
            for block in turn.get("content", []):
                text = block.get("text", "")
                if isinstance(text, str) and any(w in text.lower() for w in _REGISTRY_TRIGGER_WORDS):
                    return True
    return False


# ── Tool executors ────────────────────────────────────────────────────────────

async def _execute_get_simulation_details(run_id: str) -> str:
    try:
        async with httpx.AsyncClient(timeout=10.0) as client:
            r = await client.get(f"{JULIA_URL}/api/results/simulations/{run_id}")
            if r.status_code == 200:
                data = r.json()
                result = {
                    "run_id": data.get("run_id"),
                    "run_dir": data.get("run_dir"),
                    "catalog_entry": data.get("catalog_entry"),
                    "config": data.get("config"),
                }
                return json.dumps(result, indent=2)
            if r.status_code == 404:
                return f"No simulation found with run_id={run_id}."
            return f"Error fetching simulation details ({r.status_code}): {r.text}"
    except httpx.ConnectError:
        return "Cannot reach Julia pipeline server. Make sure it is running."
    except Exception as exc:
        return f"Error: {exc}"


async def _execute_get_observable_details(obs_run_id: str) -> str:
    try:
        async with httpx.AsyncClient(timeout=15.0) as client:
            r = await client.get(f"{JULIA_URL}/api/results/observables/{obs_run_id}")
            if r.status_code == 200:
                data = r.json()
                obs_data = data.get("data", {})
                preview: dict = {}
                for key in ("indices", "times", "energies"):
                    if obs_data.get(key):
                        preview[key] = obs_data[key][:5]
                if obs_data.get("values"):
                    preview["values_preview"] = obs_data["values"][:5]
                    preview["total_values"] = len(obs_data["values"])
                result = {
                    "obs_run_id": data.get("obs_run_id"),
                    "catalog_entry": data.get("catalog_entry"),
                    "metadata": data.get("metadata"),
                    "data_preview": preview,
                }
                return json.dumps(result, indent=2)
            if r.status_code == 404:
                return f"No observable result found with obs_run_id={obs_run_id}."
            return f"Error fetching observable details ({r.status_code}): {r.text}"
    except httpx.ConnectError:
        return "Cannot reach Julia pipeline server. Make sure it is running."
    except Exception as exc:
        return f"Error: {exc}"


async def _execute_get_run_status(tracking_id: str) -> str:
    try:
        async with httpx.AsyncClient(timeout=10.0) as client:
            r = await client.get(f"{JULIA_URL}/api/status/{tracking_id}")
            if r.status_code == 200:
                return json.dumps(r.json(), indent=2)
            return f"Status check failed ({r.status_code}): {r.text}"
    except httpx.ConnectError:
        return "Cannot reach Julia pipeline server. Make sure it is running."
    except Exception as exc:
        return f"Error: {exc}"


def _execute_get_available_models(registries: dict, system_type: str | None) -> str:
    models = registries["models"]
    result = []
    for name, entry in models["prebuilt_models"].items():
        sys = entry.get("system_type", "spin")
        if system_type and system_type not in ("all", "") and sys != system_type:
            continue
        example_params = entry.get("example_config", {}).get("model", {}).get("params", {})
        result.append({
            "name": name,
            "display_name": entry.get("display_name", name),
            "system_type": sys,
            "hamiltonian": entry.get("hamiltonian", ""),
            "description": entry.get("description", ""),
            "example_params": example_params,
        })
    user_models = models.get("user_models", {}).get("models", {})
    for uname, uentry in user_models.items():
        sys = uentry.get("system_type", "spin")
        if system_type and system_type not in ("all", "") and sys != system_type:
            continue
        result.append({
            "name": uname,
            "display_name": uentry.get("display_name", uname),
            "system_type": sys,
            "hamiltonian": uentry.get("description", "user-defined"),
            "description": uentry.get("description", ""),
            "is_user_registered": True,
        })
    if not result:
        return f"No models found for system_type={system_type!r}."
    return json.dumps(result, indent=2)


def _execute_get_available_algorithms(registries: dict) -> str:
    algorithms = registries["algorithms"]
    result = []
    for name, entry in algorithms["algorithms"].items():
        params = entry.get("params", {})
        key_params = [
            p for p, meta in params.items()
            if isinstance(meta, dict) and meta.get("required", True)
        ][:8]
        result.append({
            "type": name,
            "description": entry.get("description", ""),
            "suitable_for": entry.get("suitable_for", ""),
            "key_params": key_params,
        })
    return json.dumps(result, indent=2)


async def _execute_registration(tool_name: str, inputs: dict, on_success=None) -> str:
    """POST to the Julia server's registry endpoint and return a result string for Claude."""
    endpoint = "models" if tool_name == "register_model" else "states"
    async with httpx.AsyncClient(timeout=60.0) as client:
        try:
            r = await client.post(f"{JULIA_URL}/api/registry/{endpoint}", json=inputs)
            if r.status_code == 201:
                if on_success is not None:
                    on_success()
                return r.json().get("message", "Registered successfully.")
            return f"Registration failed ({r.status_code}): {r.text}"
        except httpx.ConnectError:
            return "Cannot reach Julia pipeline server at port 8080. Make sure it is running."
        except httpx.ReadTimeout:
            return "Julia server took too long to respond. The model may have been registered — check with 'what models can you use?' before trying again."
