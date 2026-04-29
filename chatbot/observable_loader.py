"""
Observable data loader — reads data_obs/ directly using h5py.
No Julia server dependency.

Public API
----------
find_obs_run_dir(obs_base_dir, obs_run_id) -> str
    Locate the directory for a given obs_run_id by scanning the catalog.

list_obs_runs(obs_base_dir) -> list[dict]
    Return all observable catalog entries (most recent first).

load_obs_run(obs_run_dir) -> dict
    Read one obs_run directory and return a unified dict with numpy-derived
    arrays ready for JSON serialisation or further analysis.
"""

import json
import warnings
from pathlib import Path

import h5py
import numpy as np


# ---------------------------------------------------------------------------
# Public: catalog helpers
# ---------------------------------------------------------------------------

def find_obs_run_dir(obs_base_dir: str, obs_run_id: str) -> str:
    """
    Look up the filesystem path for *obs_run_id* by scanning
    ``observables_catalog.jsonl``.

    The path is reconstructed as:
        {obs_base_dir}/{algorithm}/{sim_run_id}/{obs_run_id}

    Raises FileNotFoundError if the obs_run_id is not in the catalog or the
    directory no longer exists on disk.
    """
    obs_base = Path(obs_base_dir).resolve()
    catalog_path = obs_base / "observables_catalog.jsonl"
    if not catalog_path.exists():
        raise FileNotFoundError(f"Catalog not found: {catalog_path}")

    with catalog_path.open(encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                entry = json.loads(line)
            except json.JSONDecodeError:
                continue
            if entry.get("obs_run_id") == obs_run_id:
                algorithm = entry["simulation"]["core"]["algorithm"]
                sim_run_id = entry["sim_run_id"]
                path = obs_base / algorithm / sim_run_id / obs_run_id
                if path.is_dir():
                    return str(path)
                raise FileNotFoundError(
                    f"Catalog entry found for {obs_run_id} but directory missing: {path}"
                )

    raise FileNotFoundError(f"obs_run_id not found in catalog: {obs_run_id}")


def list_obs_runs(obs_base_dir: str) -> list:
    """
    Read ``observables_catalog.jsonl`` and return all entries as a list of
    dicts, most recent first (catalog is append-only so we reverse it).
    Returns an empty list if the catalog does not exist.
    """
    catalog_path = Path(obs_base_dir) / "observables_catalog.jsonl"
    if not catalog_path.exists():
        return []

    entries = []
    with catalog_path.open(encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                entries.append(json.loads(line))
            except json.JSONDecodeError:
                continue

    entries.reverse()
    return entries


# ---------------------------------------------------------------------------
# Public: main loader
# ---------------------------------------------------------------------------

def load_obs_run(obs_run_dir: str) -> dict:
    """
    Read one obs_run directory and return a unified result dict.

    The returned dict has the same top-level shape as the Julia server's
    ``/api/results/observables/{obs_run_id}`` response so the existing
    Plotly.js frontend works without changes.

    Parameters
    ----------
    obs_run_dir : str
        Path to an obs_run directory (contains metadata.json,
        observable_config.json, observable_sweep_N.jld2, …).

    Returns
    -------
    dict with keys:
        obs_run_id, obs_run_dir, sim_run_id, algorithm, observable_type,
        observable_params, status, sweeps_processed, metadata, config,
        data (indices, values, and optionally times / energies / bond_dims)
    """
    obs_run_dir = str(Path(obs_run_dir).resolve())
    base = Path(obs_run_dir)

    # -- 1. Load JSON sidecar files ------------------------------------------
    metadata_path = base / "metadata.json"
    config_path = base / "observable_config.json"

    if not metadata_path.exists():
        raise FileNotFoundError(f"metadata.json not found in {obs_run_dir}")

    with metadata_path.open(encoding="utf-8") as fh:
        metadata = json.load(fh)

    config = {}
    if config_path.exists():
        with config_path.open(encoding="utf-8") as fh:
            config = json.load(fh)

    # -- 2. Extract observable params from config; inject for frontend compat --
    observable_params = (
        config.get("analysis", {})
              .get("observable", {})
              .get("params", {})
    )
    metadata["params"] = observable_params

    # -- 3. Walk sweep_data (authoritative order; avoids lexicographic sort) --
    indices = []
    values = []
    times = []
    energies = []
    bond_dims = []

    for sweep_info in metadata.get("sweep_data", []):
        sweep_num = sweep_info["sweep"]
        filename = sweep_info.get("filename", f"observable_sweep_{sweep_num}.jld2")
        jld2_path = base / filename

        if not jld2_path.exists():
            warnings.warn(f"JLD2 file missing, skipping sweep {sweep_num}: {jld2_path}")
            continue

        try:
            with h5py.File(str(jld2_path), "r") as hf:
                val = _read_observable_value(hf["observable_value"])
        except Exception as exc:
            warnings.warn(f"Could not read {jld2_path}: {exc}")
            continue

        indices.append(sweep_num)
        values.append(_value_to_json(val))

        if "time" in sweep_info:
            times.append(float(sweep_info["time"]))
        if "energy" in sweep_info:
            energies.append(float(sweep_info["energy"]))
        if "max_bond_dim" in sweep_info:
            bond_dims.append(int(sweep_info["max_bond_dim"]))

    # -- 4. Assemble response -------------------------------------------------
    data_dict: dict = {"indices": indices, "values": values}
    if times:
        data_dict["times"] = times
    if energies:
        data_dict["energies"] = energies
    if bond_dims:
        data_dict["bond_dims"] = bond_dims

    return {
        "obs_run_id": metadata.get("obs_run_id", ""),
        "obs_run_dir": obs_run_dir,
        "sim_run_id": metadata.get("sim_run_id", ""),
        "algorithm": metadata.get("algorithm", ""),
        "observable_type": metadata.get("observable_type", ""),
        "observable_params": observable_params,
        "status": metadata.get("status", ""),
        "sweeps_processed": metadata.get("sweeps_processed", 0),
        "metadata": metadata,
        "config": config,
        "data": data_dict,
    }


# ---------------------------------------------------------------------------
# Private: h5py reading helpers
# ---------------------------------------------------------------------------

def _read_observable_value(dataset):
    """
    Read an h5py Dataset containing a JLD2 ``observable_value`` and return
    a plain Python / numpy value.

    JLD2 storage patterns observed in this codebase:
      - ComplexF64 scalar  → compound dtype {re: f8, im: f8}, ndim=0
      - Float64 scalar     → plain float64, ndim=0
      - Vector{Float64}    → float64 ndarray, ndim=1
      - Matrix{Float64}    → float64 ndarray, ndim=2
    """
    # dataset[()] reads the entire dataset; works for 0-D scalars and arrays
    raw = dataset[()]
    dt = raw.dtype

    if dt.names is not None and "re" in dt.names:
        # Julia ComplexF64 stored as HDF5 compound type {re, im}
        if raw.ndim == 0:
            return complex(float(raw["re"]), float(raw["im"]))
        # Future-proof: complex arrays (not currently in data but handled)
        return raw["re"] + 1j * raw["im"]

    # Plain numeric type (scalar or array)
    if raw.ndim == 0:
        return float(raw)
    return raw  # numpy ndarray; caller converts via .tolist()


def _value_to_json(val):
    """
    Convert a value from ``_read_observable_value`` to a JSON-serialisable
    form that matches the Julia server's output shape:

      - real scalar   → float
      - complex       → {"real": float, "imag": float}
      - 1-D array     → list[float]
      - 2-D array     → list[list[float]]
    """
    if isinstance(val, complex):
        return {"real": val.real, "imag": val.imag}
    if isinstance(val, (float, int, np.floating, np.integer)):
        return float(val)
    if isinstance(val, np.ndarray):
        if val.ndim == 1:
            return val.tolist()
        if val.ndim == 2:
            return [row.tolist() for row in val]
        raise ValueError(f"Unexpected ndim={val.ndim} in observable value")
    raise TypeError(f"Cannot serialise observable value of type {type(val)}")
