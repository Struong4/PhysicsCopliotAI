"""
Verification script: tests builder and validator against example configs.

Run: python mcp_bridge/tools/test_builder_validator.py
"""

import json
import os
import sys

# Add project root to path
PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, PROJECT_ROOT)

from mcp_bridge.tools.builder import build_config, fill_defaults
from mcp_bridge.tools.validator import validate_config


def load_registry():
    reg_dir = os.path.join(PROJECT_ROOT, "registry")
    registry = {}
    for name in ("models", "systems", "states", "algorithms", "config_schema"):
        path = os.path.join(reg_dir, f"{name}.json")
        with open(path) as f:
            registry[name] = json.load(f)
    return registry


def load_example(rel_path):
    path = os.path.join(PROJECT_ROOT, rel_path)
    with open(path) as f:
        return json.load(f)


def test_validator_on_examples(registry):
    """Validate all example configs — they should all pass."""
    examples = [
        "examples/00_quickstart_dmrg/heisenberg/dmrg_config.json",
        "examples/00_quickstart_dmrg/XXZ_custom/dmrg_config.json",
        "examples/00_quickstart_ed_spectrum/heisenberg_ed_spectrum_config.json",
        "examples/00_quickstart_ed_evolution/heisenberg_ed_time_evolution_config.json",
        "examples/01_quickstart_tdvp/long_range_ising/tdvp_config.json",
    ]

    print("=" * 60)
    print("TEST 1: Validator on example configs")
    print("=" * 60)

    all_passed = True
    for ex_path in examples:
        full = os.path.join(PROJECT_ROOT, ex_path)
        if not os.path.exists(full):
            print(f"  SKIP  {ex_path} (not found)")
            continue
        config = load_example(ex_path)
        result = validate_config(registry, config)
        status = "PASS" if result["valid"] else "FAIL"
        if not result["valid"]:
            all_passed = False
        print(f"  {status}  {ex_path}")
        if result["errors"]:
            for e in result["errors"]:
                print(f"         ERROR: [{e['code']}] {e['message']} @ {e['path']}")
        if result["warnings"]:
            for w in result["warnings"]:
                print(f"         WARN:  {w['message']} @ {w['path']}")

    return all_passed


def test_builder_roundtrip(registry):
    """Build configs from user params and validate the output."""
    print("\n" + "=" * 60)
    print("TEST 2: Builder round-trip")
    print("=" * 60)

    all_passed = True

    # Test 1: Heisenberg DMRG
    config = build_config(
        registry,
        system={"type": "spin", "N": 20},
        model={"name": "heisenberg", "params": {"Jx": 1.0, "Jy": 1.0, "Jz": 1.0}},
        algorithm={"type": "dmrg", "chi_max": 40, "n_sweeps": 50},
        state={"type": "random", "params": {"bond_dim": 5}},
        description="Test: Heisenberg DMRG",
    )
    result = validate_config(registry, config)
    status = "PASS" if result["valid"] else "FAIL"
    if not result["valid"]:
        all_passed = False
    print(f"  {status}  Heisenberg DMRG build")
    if result["errors"]:
        for e in result["errors"]:
            print(f"         ERROR: [{e['code']}] {e['message']}")

    # Check key fields
    assert config["system"]["type"] == "spin"
    assert config["model"]["name"] == "heisenberg"
    assert config["model"]["params"]["N"] == 20
    assert "dtype" in config["model"]["params"]
    assert config["algorithm"]["type"] == "dmrg"
    assert config["algorithm"]["options"]["chi_max"] == 40
    assert config["algorithm"]["options"]["local_dim"] == 2
    assert config["algorithm"]["solver"]["type"] == "lanczos"
    print("         Assertions passed (system, model, algorithm fields)")

    # Test 2: TFI TDVP
    config = build_config(
        registry,
        system={"type": "spin", "N": 20},
        model={"name": "transverse_field_ising", "params": {
            "J": -1.0, "h": 0.5, "coupling_dir": "Z", "field_dir": "X"
        }},
        algorithm={"type": "tdvp", "dt": 0.02, "chi_max": 60, "n_sweeps": 200},
        state={"type": "prebuilt", "name": "domain", "params": {
            "spin_direction": "Z", "start_index": 8, "domain_size": 4,
            "base_state": 1, "flip_state": 2
        }},
    )
    result = validate_config(registry, config)
    status = "PASS" if result["valid"] else "FAIL"
    if not result["valid"]:
        all_passed = False
    print(f"  {status}  TFI TDVP build")
    if result["errors"]:
        for e in result["errors"]:
            print(f"         ERROR: [{e['code']}] {e['message']}")

    # TFI with Z/X should auto-resolve to Float64
    assert config["system"]["dtype"] == "Float64", f"Expected Float64, got {config['system']['dtype']}"
    assert config["algorithm"]["solver"]["type"] == "krylov_exponential"
    print("         Assertions passed (dtype=Float64, solver type)")

    # Test 3: ED Spectrum (no state)
    config = build_config(
        registry,
        system={"type": "spin", "N": 10},
        model={"name": "heisenberg"},
        algorithm={"type": "ed_spectrum"},
    )
    result = validate_config(registry, config)
    status = "PASS" if result["valid"] else "FAIL"
    if not result["valid"]:
        all_passed = False
    print(f"  {status}  ED Spectrum build (no state)")
    assert "state" not in config, "ED spectrum should have no state block"
    print("         Assertions passed (no state block)")

    # Test 4: ED Time Evolution (with state)
    config = build_config(
        registry,
        system={"type": "spin", "N": 10},
        model={"name": "heisenberg"},
        algorithm={"type": "ed_time_evolution", "dt": 0.05, "n_steps": 200},
        state={"type": "prebuilt", "name": "polarized", "params": {
            "spin_direction": "Z", "eigenstate": 1
        }},
    )
    result = validate_config(registry, config)
    status = "PASS" if result["valid"] else "FAIL"
    if not result["valid"]:
        all_passed = False
    print(f"  {status}  ED Time Evolution build")
    assert "state" in config, "ED time evolution should have state block"
    print("         Assertions passed (has state block)")

    # Test 5: Custom XXZ model
    config = build_config(
        registry,
        system={"type": "spin", "N": 20},
        model={"name": "custom_spin", "params": {
            "channels": [
                {"type": "FiniteRangeCoupling", "op1": "X", "op2": "X", "range": 1, "strength": 1.0},
                {"type": "FiniteRangeCoupling", "op1": "Y", "op2": "Y", "range": 1, "strength": 1.0},
                {"type": "FiniteRangeCoupling", "op1": "Z", "op2": "Z", "range": 1, "strength": 2.0},
                {"type": "Field", "op": "Z", "strength": 0.5},
            ]
        }},
        algorithm={"type": "dmrg", "chi_max": 40, "n_sweeps": 50},
        state={"type": "random", "params": {"bond_dim": 5}},
    )
    result = validate_config(registry, config)
    status = "PASS" if result["valid"] else "FAIL"
    if not result["valid"]:
        all_passed = False
    print(f"  {status}  Custom XXZ DMRG build")
    # Y operator should force ComplexF64
    assert config["system"]["dtype"] == "ComplexF64", f"Expected ComplexF64, got {config['system']['dtype']}"
    assert "channels" in config["model"]["params"], "TN custom should use 'channels'"
    assert config["model"]["params"]["d"] == 2, "TN custom spin should have d=2"
    print("         Assertions passed (ComplexF64, channels key, d=2)")

    return all_passed


def test_dtype_resolution(registry):
    """Test dtype auto-resolution for various models."""
    print("\n" + "=" * 60)
    print("TEST 3: dtype auto-resolution")
    print("=" * 60)

    all_passed = True

    # Heisenberg with Jy=0 -> Float64
    config = build_config(
        registry,
        system={"type": "spin", "N": 10},
        model={"name": "heisenberg", "params": {"Jx": 1.0, "Jy": 0, "Jz": 1.0, "hx": 0, "hy": 0, "hz": 0}},
        algorithm={"type": "dmrg"},
    )
    dtype = config["system"]["dtype"]
    ok = dtype == "Float64"
    if not ok:
        all_passed = False
    print(f"  {'PASS' if ok else 'FAIL'}  Heisenberg Jy=0 -> {dtype} (expected Float64)")

    # Heisenberg with Jy=1 -> ComplexF64
    config = build_config(
        registry,
        system={"type": "spin", "N": 10},
        model={"name": "heisenberg", "params": {"Jx": 1.0, "Jy": 1.0, "Jz": 1.0, "hx": 0, "hy": 0, "hz": 0}},
        algorithm={"type": "dmrg"},
    )
    dtype = config["system"]["dtype"]
    ok = dtype == "ComplexF64"
    if not ok:
        all_passed = False
    print(f"  {'PASS' if ok else 'FAIL'}  Heisenberg Jy=1 -> {dtype} (expected ComplexF64)")

    # TFI with Z/X -> Float64
    config = build_config(
        registry,
        system={"type": "spin", "N": 10},
        model={"name": "transverse_field_ising", "params": {
            "J": -1.0, "h": 0.5, "coupling_dir": "Z", "field_dir": "X"
        }},
        algorithm={"type": "dmrg"},
    )
    dtype = config["system"]["dtype"]
    ok = dtype == "Float64"
    if not ok:
        all_passed = False
    print(f"  {'PASS' if ok else 'FAIL'}  TFI Z/X -> {dtype} (expected Float64)")

    # TFI with Y field -> ComplexF64
    config = build_config(
        registry,
        system={"type": "spin", "N": 10},
        model={"name": "transverse_field_ising", "params": {
            "J": -1.0, "h": 0.5, "coupling_dir": "Z", "field_dir": "Y"
        }},
        algorithm={"type": "dmrg"},
    )
    dtype = config["system"]["dtype"]
    ok = dtype == "ComplexF64"
    if not ok:
        all_passed = False
    print(f"  {'PASS' if ok else 'FAIL'}  TFI Z/Y -> {dtype} (expected ComplexF64)")

    # Custom with only X/Z operators -> Float64
    config = build_config(
        registry,
        system={"type": "spin", "N": 10},
        model={"name": "custom_spin", "params": {
            "channels": [
                {"type": "EDCoupling", "op1": "Z", "op2": "Z", "pattern": "nearest_neighbor", "strength": 1.0},
                {"type": "EDField", "op": "X", "strength": 0.5},
            ]
        }},
        algorithm={"type": "dmrg"},
    )
    dtype = config["system"]["dtype"]
    ok = dtype == "Float64"
    if not ok:
        all_passed = False
    print(f"  {'PASS' if ok else 'FAIL'}  Custom Z/X only -> {dtype} (expected Float64)")

    # Custom with Y operator -> ComplexF64
    config = build_config(
        registry,
        system={"type": "spin", "N": 10},
        model={"name": "custom_spin", "params": {
            "channels": [
                {"type": "EDCoupling", "op1": "Y", "op2": "Y", "pattern": "nearest_neighbor", "strength": 1.0},
            ]
        }},
        algorithm={"type": "dmrg"},
    )
    dtype = config["system"]["dtype"]
    ok = dtype == "ComplexF64"
    if not ok:
        all_passed = False
    print(f"  {'PASS' if ok else 'FAIL'}  Custom with Y -> {dtype} (expected ComplexF64)")

    return all_passed


def test_validator_errors(registry):
    """Test that broken configs produce correct error codes."""
    print("\n" + "=" * 60)
    print("TEST 4: Validator error detection")
    print("=" * 60)

    all_passed = True

    # Missing system
    r = validate_config(registry, {"model": {"name": "heisenberg"}, "algorithm": {"type": "dmrg"}})
    ok = not r["valid"] and any(e["code"] == "MISSING_FIELD" for e in r["errors"])
    if not ok:
        all_passed = False
    print(f"  {'PASS' if ok else 'FAIL'}  Missing system -> MISSING_FIELD")

    # Unknown model
    r = validate_config(registry, {
        "system": {"type": "spin", "N": 10, "S": 0.5, "dtype": "ComplexF64"},
        "model": {"name": "nonexistent_model"},
        "algorithm": {"type": "dmrg"},
        "state": {"type": "random", "params": {"bond_dim": 5}},
    })
    ok = not r["valid"] and any(e["code"] == "UNKNOWN_MODEL" for e in r["errors"])
    if not ok:
        all_passed = False
    print(f"  {'PASS' if ok else 'FAIL'}  Unknown model -> UNKNOWN_MODEL")

    # ED Spectrum too large (N=16, S=0.5)
    r = validate_config(registry, {
        "system": {"type": "spin", "N": 16, "S": 0.5, "dtype": "ComplexF64"},
        "model": {"name": "heisenberg", "params": {"N": 16, "Jx": 1, "Jy": 1, "Jz": 1, "hx": 0, "hy": 0, "hz": 0, "dtype": "ComplexF64"}},
        "algorithm": {"type": "ed_spectrum"},
    })
    ok = not r["valid"] and any(e["code"] == "SIZE_EXCEEDS_LIMIT" for e in r["errors"])
    if not ok:
        all_passed = False
    print(f"  {'PASS' if ok else 'FAIL'}  ED N=16 S=0.5 -> SIZE_EXCEEDS_LIMIT")

    # State required but missing (DMRG)
    r = validate_config(registry, {
        "system": {"type": "spin", "N": 10, "S": 0.5, "dtype": "ComplexF64"},
        "model": {"name": "heisenberg", "params": {"N": 10, "Jx": 1, "Jy": 1, "Jz": 1, "hx": 0, "hy": 0, "hz": 0, "dtype": "ComplexF64"}},
        "algorithm": {"type": "dmrg", "solver": {"type": "lanczos", "krylov_dim": 20, "max_iter": 10}, "options": {"chi_max": 64, "cutoff": 1e-10, "local_dim": 2}, "run": {"n_sweeps": 20}},
    })
    ok = not r["valid"] and any(e["code"] == "STATE_REQUIRED" for e in r["errors"])
    if not ok:
        all_passed = False
    print(f"  {'PASS' if ok else 'FAIL'}  DMRG no state -> STATE_REQUIRED")

    # Float64 with Y operator -> DTYPE_UNSAFE
    r = validate_config(registry, {
        "system": {"type": "spin", "N": 10, "S": 0.5, "dtype": "Float64"},
        "model": {"name": "heisenberg", "params": {"N": 10, "Jx": 1, "Jy": 1.0, "Jz": 1, "hx": 0, "hy": 0, "hz": 0, "dtype": "Float64"}},
        "algorithm": {"type": "ed_spectrum"},
    })
    ok = not r["valid"] and any(e["code"] == "DTYPE_UNSAFE" for e in r["errors"])
    if not ok:
        all_passed = False
    print(f"  {'PASS' if ok else 'FAIL'}  Float64 + Jy=1 -> DTYPE_UNSAFE")

    # use_sparse=true without n_states
    r = validate_config(registry, {
        "system": {"type": "spin", "N": 10, "S": 0.5, "dtype": "ComplexF64"},
        "model": {"name": "heisenberg", "params": {"N": 10, "Jx": 1, "Jy": 0, "Jz": 1, "hx": 0, "hy": 0, "hz": 0, "dtype": "ComplexF64"}},
        "algorithm": {"type": "ed_spectrum", "use_sparse": True},
    })
    ok = not r["valid"] and any(e["code"] == "SPARSE_REQUIRES_NSTATES" for e in r["errors"])
    if not ok:
        all_passed = False
    print(f"  {'PASS' if ok else 'FAIL'}  use_sparse=true no n_states -> SPARSE_REQUIRES_NSTATES")

    # Custom state wrong array length
    r = validate_config(registry, {
        "system": {"type": "spin", "N": 5, "S": 0.5, "dtype": "ComplexF64"},
        "model": {"name": "custom_spin", "params": {"N": 5, "dtype": "ComplexF64", "terms": [{"type": "EDField", "op": "Z", "strength": 1.0}]}},
        "algorithm": {"type": "ed_time_evolution", "dt": 0.1, "n_steps": 10},
        "state": {"type": "custom", "site_configs": [["Z", 1], ["Z", 2], ["Z", 1]]},
    })
    ok = not r["valid"] and any(e["code"] == "ARRAY_LENGTH_MISMATCH" for e in r["errors"])
    if not ok:
        all_passed = False
    print(f"  {'PASS' if ok else 'FAIL'}  Custom state wrong length -> ARRAY_LENGTH_MISMATCH")

    return all_passed


def test_zero_hardcoding(registry):
    """Grep builder.py for hardcoded algorithm/model names."""
    print("\n" + "=" * 60)
    print("TEST 5: Zero hardcoding check")
    print("=" * 60)

    builder_path = os.path.join(PROJECT_ROOT, "mcp_bridge", "tools", "builder.py")
    with open(builder_path) as f:
        code = f.read()

    # These strings should NOT appear as hardcoded values in logic
    # (they can appear in docstrings/comments but not in if/elif conditions)
    forbidden_patterns = [
        'if algo_type == "dmrg"',
        'if algo_type == "tdvp"',
        'if algo_type == "ed_spectrum"',
        'if algo_type == "ed_time_evolution"',
        'if model_name == "heisenberg"',
        'if model_name == "transverse_field_ising"',
        'if backend_category == "tensor_network"',  # This should be read from schema, not hardcoded
        '"spin_label"' not in code,  # Should come from schema
    ]

    found_issues = []
    for pattern in forbidden_patterns:
        if isinstance(pattern, str) and pattern in code:
            found_issues.append(pattern)

    ok = len(found_issues) == 0
    print(f"  {'PASS' if ok else 'FAIL'}  No hardcoded algorithm/model name checks in builder.py")
    if found_issues:
        for p in found_issues:
            print(f"         Found: {p}")

    return ok


def main():
    registry = load_registry()
    print(f"Registry loaded: {list(registry.keys())}")
    print()

    results = []
    results.append(("Validator on examples", test_validator_on_examples(registry)))
    results.append(("Builder round-trip", test_builder_roundtrip(registry)))
    results.append(("dtype resolution", test_dtype_resolution(registry)))
    results.append(("Validator errors", test_validator_errors(registry)))
    results.append(("Zero hardcoding", test_zero_hardcoding(registry)))

    print("\n" + "=" * 60)
    print("SUMMARY")
    print("=" * 60)
    all_ok = True
    for name, passed in results:
        status = "PASS" if passed else "FAIL"
        if not passed:
            all_ok = False
        print(f"  {status}  {name}")

    print()
    if all_ok:
        print("All tests passed!")
    else:
        print("Some tests FAILED.")
        sys.exit(1)


if __name__ == "__main__":
    main()
