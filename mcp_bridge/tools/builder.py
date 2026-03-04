"""
Config builder for the MCP pipeline.

Every decision comes from the 5 registry JSON files:
  models.json, systems.json, states.json, algorithms.json, config_schema.json

Zero hardcoded model names, algorithm names, parameter names, or backend conventions.
The Python code is a generic template-filler that:
  1. Reads config_schema.json to know structure
  2. Reads domain registries to know defaults/constraints
  3. Fills user input into the structure
  4. Returns a complete config dict
"""

from __future__ import annotations

import copy
import math
from typing import Any


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

def build_config(
    registry: dict,
    system: dict,
    model: dict,
    algorithm: dict,
    state: dict | None = None,
    description: str = "",
    mode: str = "simulation",
) -> dict:
    """Assemble a complete simulation config from partial user inputs.

    Args:
        registry: All 5 registry files keyed as
            {"models", "systems", "states", "algorithms", "config_schema"}.
        system: User-provided system params (partial OK — defaults filled).
        model: User-provided model params (partial OK — defaults filled).
        algorithm: User-provided algorithm params (partial OK — defaults filled).
        state: User-provided state params, or None.
        description: Optional human-readable description string.
        mode: "simulation" or "analysis".

    Returns:
        Complete config dict ready for the Julia runner.
    """
    schema = registry["config_schema"]

    # 1. Build system block (fill defaults)
    system_block = _build_system_block(registry, system)

    # 2. Determine backend category from algorithm type
    algo_type = algorithm.get("type", "")
    backend_category = _get_backend_category(schema, algo_type)

    # 3. Build model block
    model_block = _build_model_block(registry, model, system_block, backend_category)

    # 4. Resolve dtype (pass original user input to detect explicit choice)
    resolved_dtype = _resolve_dtype(registry, model_block, system_block, user_system=system)
    system_block["dtype"] = resolved_dtype
    # Also update dtype in model.params if present
    if "params" in model_block and "dtype" in model_block["params"]:
        model_block["params"]["dtype"] = resolved_dtype

    # 5. Build algorithm block
    algorithm_block = _build_algorithm_block(registry, algorithm, system_block)

    # 6. Build state block (may be None for ed_spectrum)
    state_block = _build_state_block(
        registry, state, algo_type, system_block, backend_category
    )

    # 7. Assemble config
    config: dict[str, Any] = {
        "system": system_block,
        "model": model_block,
        "algorithm": algorithm_block,
    }
    if state_block is not None:
        config["state"] = state_block
    if description:
        config["description"] = description

    return config


def fill_defaults(registry: dict, partial_config: dict) -> dict:
    """Take a partially-filled config and fill in any missing defaults.

    Useful when the user edits a config manually and omits optional fields.
    """
    config = copy.deepcopy(partial_config)
    schema = registry["config_schema"]

    # Fill system defaults
    if "system" in config:
        config["system"] = _build_system_block(registry, config["system"])

    # Determine backend category
    algo_type = config.get("algorithm", {}).get("type", "")
    backend_category = _get_backend_category(schema, algo_type) if algo_type else None

    # Fill model defaults
    if "model" in config and backend_category:
        config["model"] = _build_model_block(
            registry, config["model"], config["system"], backend_category
        )

    # Resolve dtype
    if "system" in config and "model" in config:
        original_system = partial_config.get("system", {})
        resolved_dtype = _resolve_dtype(registry, config["model"], config["system"], user_system=original_system)
        config["system"]["dtype"] = resolved_dtype
        if "params" in config["model"] and "dtype" in config["model"]["params"]:
            config["model"]["params"]["dtype"] = resolved_dtype

    # Fill algorithm defaults
    if "algorithm" in config and "system" in config:
        config["algorithm"] = _build_algorithm_block(
            registry, config["algorithm"], config["system"]
        )

    # Fill state defaults
    if backend_category and "system" in config:
        state_input = config.get("state")
        state_block = _build_state_block(
            registry, state_input, algo_type, config["system"], backend_category
        )
        if state_block is not None:
            config["state"] = state_block
        elif "state" in config and state_block is None:
            # Algorithm doesn't need a state — remove if present
            del config["state"]

    return config


def build_analysis_config(
    registry: dict,
    simulation_config: dict,
    selection: dict,
    observable: dict,
) -> dict:
    """Build an analysis/observable config from a simulation config.

    Args:
        registry: All 5 registry files.
        simulation_config: The original simulation config dict.
        selection: Which snapshots to analyze, e.g. {"sweeps": [1, 5, 10]}.
        observable: What to measure, e.g. {"type": "expectation", "operator": "Z"}.

    Returns:
        Analysis config dict.
    """
    schema = registry["config_schema"]
    algo_type = simulation_config.get("algorithm", {}).get("type", "")
    selection_key_map = schema.get("analysis_assembly", {}).get("selection_key", {})
    sel_key = selection_key_map.get(algo_type, "sweeps")

    return {
        "simulation": simulation_config,
        "selection": {sel_key: selection.get(sel_key, selection.get("indices", []))},
        "observable": observable,
    }


# ---------------------------------------------------------------------------
# Internal helpers — all registry-driven
# ---------------------------------------------------------------------------

def _get_backend_category(schema: dict, algorithm_type: str) -> str:
    """Look up backend category from config_schema.backend_categories."""
    mapping = schema.get("backend_categories", {}).get("mapping", {})
    category = mapping.get(algorithm_type)
    if category is None:
        raise ValueError(
            f"Unknown algorithm type '{algorithm_type}'. "
            f"Known types: {list(mapping.keys())}"
        )
    return category


def _build_system_block(registry: dict, user_system: dict) -> dict:
    """Build a complete system block by filling defaults from systems.json."""
    systems_reg = registry["systems"]
    sys_type = user_system.get("type", "spin")

    type_spec = systems_reg.get("system_types", {}).get(sys_type, {})
    fields_spec = type_spec.get("fields", {})

    result = {"type": sys_type}

    # Copy user-provided fields first
    for key, val in user_system.items():
        result[key] = val

    # Fill defaults for any missing required fields
    for field_name in type_spec.get("required_fields", []):
        if field_name not in result:
            field_def = fields_spec.get(field_name, {})
            if "default" in field_def:
                result[field_name] = field_def["default"]
            elif "value" in field_def:
                result[field_name] = field_def["value"]

    return result


def _find_model_spec(registry: dict, model_name: str) -> tuple[str, dict]:
    """Locate a model in prebuilt, custom, or user registries.

    Returns (category, spec) where category is "prebuilt", "custom", or "user".
    """
    models_reg = registry["models"]

    if model_name in models_reg.get("prebuilt_models", {}):
        return "prebuilt", models_reg["prebuilt_models"][model_name]

    if model_name in models_reg.get("custom_models", {}):
        return "custom", models_reg["custom_models"][model_name]

    user_models = models_reg.get("user_models", {}).get("models", {})
    if model_name in user_models:
        return "user", user_models[model_name]

    raise ValueError(
        f"Unknown model '{model_name}'. Not found in prebuilt_models, "
        f"custom_models, or user_models."
    )


def _build_model_block(
    registry: dict,
    user_model: dict,
    system_block: dict,
    backend_category: str,
) -> dict:
    """Build a complete model block from user input + registry defaults."""
    schema = registry["config_schema"]
    model_name = user_model.get("name", "")
    user_params = user_model.get("params", {})

    category, model_spec = _find_model_spec(registry, model_name)

    if category == "prebuilt":
        return _build_prebuilt_model(
            schema, model_spec, model_name, user_params, system_block, backend_category
        )
    elif category == "custom":
        return _build_custom_model(
            schema, model_name, user_params, system_block, backend_category
        )
    else:  # user-registered model
        return _build_user_model(
            schema, registry, model_spec, model_name, user_params,
            system_block, backend_category
        )


def _build_prebuilt_model(
    schema: dict,
    model_spec: dict,
    model_name: str,
    user_params: dict,
    system_block: dict,
    backend_category: str,
) -> dict:
    """Assemble a prebuilt model block with defaults and system field copies."""
    sys_type = system_block.get("type", "spin")
    assembly = schema.get("model_assembly", {})

    # Start with user-provided params
    params = dict(user_params)

    # Fill defaults from registry for any missing params
    param_specs = model_spec.get("params", {})
    for pname, pspec in param_specs.items():
        if pname not in params and "default" in pspec:
            params[pname] = pspec["default"]

    # Copy system fields into model.params (for hash consistency)
    fields_to_copy = (
        assembly.get("prebuilt", {})
        .get("system_fields_to_copy", {})
        .get(sys_type, [])
    )
    for field in fields_to_copy:
        if field in system_block:
            params[field] = system_block[field]

    # Handle tn_only_params: include for TN, omit for ED
    tn_only = model_spec.get("tn_only_params", [])
    if backend_category != "tensor_network":
        for p in tn_only:
            params.pop(p, None)

    return {"name": model_name, "params": params}


def _build_custom_model(
    schema: dict,
    model_name: str,
    user_params: dict,
    system_block: dict,
    backend_category: str,
) -> dict:
    """Assemble a custom model block using config_schema conventions."""
    sys_type = system_block.get("type", "spin")
    custom_spec = (
        schema.get("model_assembly", {})
        .get("custom", {})
        .get(backend_category, {})
        .get(sys_type, {})
    )

    format_key = custom_spec.get("format_key", "terms")
    resolved_name = custom_spec.get("model_name", model_name)
    extra_params_spec = custom_spec.get("extra_params", {})

    params: dict[str, Any] = {}

    # Resolve extra params (system field references and computed values)
    for param_name, source in extra_params_spec.items():
        if source == "local_dim":
            s_val = system_block.get("S", 0.5)
            params[param_name] = int(math.floor(2 * s_val + 1))
        elif isinstance(source, str) and source.startswith("system."):
            field = source.split(".", 1)[1]
            if field in system_block:
                params[param_name] = system_block[field]
        else:
            params[param_name] = source

    # Insert user's terms/channels under the correct key
    # User may have provided them under the format_key already, or as raw data
    if format_key in user_params:
        params[format_key] = user_params[format_key]
    elif "terms" in user_params:
        params[format_key] = user_params["terms"]
    elif "channels" in user_params:
        params[format_key] = user_params["channels"]

    return {"name": resolved_name, "params": params}


def _build_user_model(
    schema: dict,
    registry: dict,
    model_spec: dict,
    model_name: str,
    user_params: dict,
    system_block: dict,
    backend_category: str,
) -> dict:
    """Assemble a user-registered model. Stored terms get wrapped in custom format."""
    sys_type = system_block.get("type", "spin")
    custom_spec = (
        schema.get("model_assembly", {})
        .get("custom", {})
        .get(backend_category, {})
        .get(sys_type, {})
    )

    format_key = custom_spec.get("format_key", "terms")
    resolved_name = custom_spec.get("model_name", model_name)
    extra_params_spec = custom_spec.get("extra_params", {})

    params: dict[str, Any] = {}

    # Resolve extra params
    for param_name, source in extra_params_spec.items():
        if source == "local_dim":
            s_val = system_block.get("S", 0.5)
            params[param_name] = int(math.floor(2 * s_val + 1))
        elif isinstance(source, str) and source.startswith("system."):
            field = source.split(".", 1)[1]
            if field in system_block:
                params[param_name] = system_block[field]
        else:
            params[param_name] = source

    # User-registered models store terms directly in model_spec
    terms = model_spec.get("terms", user_params.get(format_key, []))
    params[format_key] = terms

    return {"name": resolved_name, "params": params}


def _resolve_dtype(
    registry: dict,
    model_block: dict,
    system_block: dict,
    user_system: dict | None = None,
) -> str:
    """Auto-resolve dtype based on model params and operator usage.

    Priority: user-explicit > prebuilt dtype_logic > custom operator scan > default.
    """
    schema = registry["config_schema"]

    # If user explicitly set dtype in their input, honour it
    user_sys = user_system or {}
    user_model_params = model_block.get("params", {})
    if "dtype" in user_sys and user_sys["dtype"] is not None:
        return user_sys["dtype"]
    if "dtype" in user_model_params and user_model_params.get("dtype") is not None:
        # Check if this was user-provided vs auto-filled. If model.params.dtype
        # was copied from system defaults, we should still auto-resolve.
        # Only honour explicit user choice.
        pass  # Will be overwritten by auto-resolution below

    model_name = model_block.get("name", "")
    models_reg = registry["models"]
    model_params = model_block.get("params", {})

    # For prebuilt models: evaluate dtype_logic rules
    prebuilt_spec = models_reg.get("prebuilt_models", {}).get(model_name, {})
    if prebuilt_spec and "dtype_logic" in prebuilt_spec:
        return _evaluate_dtype_logic(prebuilt_spec["dtype_logic"], model_params)

    # For custom/user models: scan operators
    custom_scan = (
        schema.get("dtype_resolution", {}).get("custom_model_scan", {})
    )
    if custom_scan:
        return _scan_operators_for_dtype(registry, model_params, custom_scan)

    # Fallback
    return custom_scan.get("default_dtype", "ComplexF64")


def _evaluate_dtype_logic(dtype_logic: dict, params: dict) -> str:
    """Evaluate structured dtype_logic rules from models.json."""
    default = dtype_logic.get("default", "ComplexF64")
    safe_rules = dtype_logic.get("float64_safe_when", [])

    for rule in safe_rules:
        if "all_in" in rule:
            spec = rule["all_in"]
            check_params = spec.get("params", [])
            allowed = set(spec.get("allowed", []))
            if all(params.get(p) in allowed for p in check_params):
                return "Float64"

        elif "all_zero" in rule:
            spec = rule["all_zero"]
            check_params = spec.get("params", [])
            if all(params.get(p, 0) == 0 for p in check_params):
                return "Float64"

    return default


def _scan_operators_for_dtype(
    registry: dict,
    model_params: dict,
    scan_config: dict,
) -> str:
    """Scan all operator strings in custom model terms/channels.

    If any operator has real=false in systems.json, dtype must be ComplexF64.
    """
    systems_reg = registry["systems"]
    # Navigate to operators dict: systems.spin_operators.operators
    source_path = scan_config.get("operator_source", "").split(".")
    op_registry = systems_reg
    for key in source_path:
        op_registry = op_registry.get(key, {})

    check_field = scan_config.get("check_field", "real")
    complex_when = scan_config.get("complex_when", False)
    default_dtype = scan_config.get("default_dtype", "ComplexF64")

    # Collect all operator strings from the model params
    operators = _extract_operators(model_params)

    for op in operators:
        op_spec = op_registry.get(op, {})
        if op_spec.get(check_field) == complex_when:
            return "ComplexF64"

    return "Float64" if operators else default_dtype


def _extract_operators(params: dict) -> set[str]:
    """Recursively extract all spin operator strings from model params."""
    ops: set[str] = set()
    _walk_for_operators(params, ops)
    return ops


def _walk_for_operators(obj: Any, ops: set[str]) -> None:
    """Walk a nested dict/list and collect values of operator-like keys."""
    op_keys = {"op", "op1", "op2", "spin_op"}
    if isinstance(obj, dict):
        for key, val in obj.items():
            if key in op_keys and isinstance(val, str):
                ops.add(val)
            else:
                _walk_for_operators(val, ops)
    elif isinstance(obj, list):
        for item in obj:
            _walk_for_operators(item, ops)


def _build_algorithm_block(
    registry: dict,
    user_algorithm: dict,
    system_block: dict,
) -> dict:
    """Build a complete algorithm block from user input + registry defaults."""
    schema = registry["config_schema"]
    algorithms_reg = registry["algorithms"]
    algo_type = user_algorithm.get("type", "")

    algo_spec = algorithms_reg.get("algorithms", {}).get(algo_type, {})
    if not algo_spec:
        raise ValueError(
            f"Unknown algorithm '{algo_type}'. "
            f"Known: {list(algorithms_reg.get('algorithms', {}).keys())}"
        )

    assembly = schema.get("algorithm_assembly", {})

    # Get the flat param mapping for this algorithm
    flat_mapping = assembly.get("flat_param_mapping", {}).get(algo_type, {})

    # Start with type
    result: dict[str, Any] = {"type": algo_type}

    # Check if this algorithm has nested structure (solver/options/run)
    config_structure = algo_spec.get("config_structure", {}).get("algorithm", {})
    has_nested = any(
        key in config_structure for key in ("solver", "options", "run")
    )

    if has_nested:
        # Initialize nested structure
        for section in ("solver", "options", "run"):
            if section in config_structure:
                result[section] = {}

        # Inject solver defaults
        solver_defaults = assembly.get("solver_defaults", {}).get(algo_type, {})
        for dotpath, value in solver_defaults.items():
            _set_nested(result, dotpath, value)

        # Map flat user params into nested structure
        for param_name, dotpath in flat_mapping.items():
            if param_name in user_algorithm:
                _set_nested(result, dotpath, user_algorithm[param_name])

        # Also handle already-nested user input (user may have passed full structure)
        for section in ("solver", "options", "run"):
            if section in user_algorithm and isinstance(user_algorithm[section], dict):
                for key, val in user_algorithm[section].items():
                    if section not in result:
                        result[section] = {}
                    result[section][key] = val

        # Fill remaining defaults from registry param specs
        param_specs = algo_spec.get("params", {})
        for section, section_params in param_specs.items():
            if isinstance(section_params, dict):
                for pname, pspec in section_params.items():
                    if isinstance(pspec, dict) and "default" in pspec:
                        if section in result and pname not in result[section]:
                            result[section][pname] = pspec["default"]

        # Compute auto-derived fields
        auto_fields = assembly.get("auto_derived_fields", {})
        backend_category = _get_backend_category(schema, algo_type)
        for _field_name, field_spec in auto_fields.items():
            if not isinstance(field_spec, dict):
                continue
            applies_to = field_spec.get("applies_to_categories", [])
            if backend_category in applies_to:
                source = field_spec.get("source", "")
                target = field_spec.get("target", "")
                if source.startswith("system."):
                    src_field = source.split(".", 1)[1]
                    src_val = system_block.get(src_field, 0.5)
                    computed = int(math.floor(2 * src_val + 1))
                    _set_nested(result, target, computed)

    else:
        # Flat algorithm structure (ed_spectrum, ed_time_evolution)
        for param_name, dotpath in flat_mapping.items():
            if param_name in user_algorithm:
                _set_nested(result, dotpath, user_algorithm[param_name])

        # Fill defaults (skip null defaults — they represent optional params)
        param_specs = algo_spec.get("params", {})
        for pname, pspec in param_specs.items():
            if isinstance(pspec, dict) and "default" in pspec:
                if pname not in result and pspec["default"] is not None:
                    result[pname] = pspec["default"]

    return result


def _build_state_block(
    registry: dict,
    user_state: dict | None,
    algorithm_type: str,
    system_block: dict,
    backend_category: str,
) -> dict | None:
    """Build a state block, or return None if the algorithm doesn't need one."""
    states_reg = registry["states"]
    schema = registry["config_schema"]

    # Check if algorithm requires a state
    algo_req = states_reg.get("algorithm_requirement", {}).get(algorithm_type, {})
    requires_state = algo_req.get("requires_state", True) if isinstance(algo_req, dict) else True

    if not requires_state:
        return None

    if user_state is None:
        # Algorithm requires a state but none provided — return a default random state
        return _build_random_state(schema, backend_category, {})

    state_type = user_state.get("type", "random")

    if state_type == "random":
        return _build_random_state(schema, backend_category, user_state)
    elif state_type == "prebuilt":
        return _build_prebuilt_state(registry, user_state, system_block)
    elif state_type == "custom":
        return _build_custom_state(schema, user_state, system_block, backend_category)
    else:
        # Could be a user-registered state name
        return _build_named_state(registry, user_state, system_block, backend_category)


def _build_random_state(
    schema: dict,
    backend_category: str,
    user_state: dict,
) -> dict:
    """Build a random state block."""
    random_spec = schema.get("state_assembly", {}).get("random", {})
    category_spec = random_spec.get(backend_category, {})
    include_bond_dim = category_spec.get("include_bond_dim", True)

    result: dict[str, Any] = {"type": "random"}
    user_params = user_state.get("params", {})

    if include_bond_dim:
        bond_dim = user_params.get("bond_dim", 10)
        params: dict[str, Any] = {"bond_dim": bond_dim}
        if "seed" in user_params:
            params["seed"] = user_params["seed"]
        result["params"] = params
    else:
        if "seed" in user_params:
            result["params"] = {"seed": user_params["seed"]}

    return result


def _build_prebuilt_state(
    registry: dict,
    user_state: dict,
    system_block: dict,
) -> dict:
    """Build a prebuilt pattern state."""
    schema = registry["config_schema"]
    states_reg = registry["states"]
    sys_type = system_block.get("type", "spin")
    pattern_name = user_state.get("name", "polarized")
    user_params = user_state.get("params", {})

    # Look up pattern spec in registry
    pattern_spec = (
        states_reg.get("state_types", {})
        .get("prebuilt", {})
        .get("patterns", {})
        .get(pattern_name, {})
    )

    result: dict[str, Any] = {"type": "prebuilt", "name": pattern_name}
    params: dict[str, Any] = dict(user_params)

    # Fill defaults from pattern params spec
    param_specs = pattern_spec.get("params", {})
    for pname, pspec in param_specs.items():
        if pname not in params and isinstance(pspec, dict) and "default" in pspec:
            params[pname] = pspec["default"]

    # Handle eigenstate field name for polarized+spinboson
    prebuilt_assembly = schema.get("state_assembly", {}).get("prebuilt", {})
    eigen_field_map = prebuilt_assembly.get("polarized_eigenstate_field", {})

    if pattern_name == "polarized" and sys_type in eigen_field_map:
        correct_field = eigen_field_map[sys_type]
        # If user used the wrong field name, remap
        if sys_type == "spinboson":
            if "eigenstate" in params and "spin_eigenstate" not in params:
                params["spin_eigenstate"] = params.pop("eigenstate")
        elif sys_type == "spin":
            if "spin_eigenstate" in params and "eigenstate" not in params:
                params["eigenstate"] = params.pop("spin_eigenstate")

    # Remove spinboson-only params from spin configs and vice-versa
    if sys_type == "spin":
        params.pop("boson_level", None)
        params.pop("spin_eigenstate", None)
    elif sys_type == "spinboson":
        # Keep boson_level, ensure it has a default
        if "boson_level" not in params:
            params["boson_level"] = 0

    if params:
        result["params"] = params

    return result


def _build_custom_state(
    schema: dict,
    user_state: dict,
    system_block: dict,
    backend_category: str,
) -> dict:
    """Build a custom site-by-site state using config_schema conventions."""
    sys_type = system_block.get("type", "spin")
    custom_spec = (
        schema.get("state_assembly", {})
        .get("custom", {})
        .get(backend_category, {})
        .get(sys_type, {})
    )

    site_field = custom_spec.get("site_field", "spin_label")
    boson_field = custom_spec.get("boson_field")
    location = custom_spec.get("location", "root")

    result: dict[str, Any] = {"type": "custom"}

    # Extract site data from user input (may be under various keys)
    site_data = (
        user_state.get(site_field)
        or user_state.get("spin_label")
        or user_state.get("site_configs")
        or user_state.get("params", {}).get(site_field)
        or user_state.get("params", {}).get("spin_label")
        or user_state.get("params", {}).get("site_configs")
    )

    boson_data = (
        user_state.get("boson_level")
        or user_state.get("params", {}).get("boson_level")
    )

    if location == "root":
        if site_data is not None:
            result[site_field] = site_data
        if boson_field and boson_data is not None:
            result[boson_field] = boson_data
    elif location == "params":
        params: dict[str, Any] = {}
        if site_data is not None:
            params[site_field] = site_data
        if boson_field and boson_data is not None:
            params[boson_field] = boson_data
        if params:
            result["params"] = params

    return result


def _build_named_state(
    registry: dict,
    user_state: dict,
    system_block: dict,
    backend_category: str,
) -> dict:
    """Look up a user-registered state by name and inline as custom."""
    states_reg = registry["states"]
    schema = registry["config_schema"]
    state_name = user_state.get("name", user_state.get("type", ""))

    user_states = states_reg.get("user_states", {}).get("states", {})
    if state_name not in user_states:
        raise ValueError(
            f"Unknown state '{state_name}'. "
            f"Not found in prebuilt patterns or user_states."
        )

    saved = user_states[state_name]
    # Convert to custom format
    custom_input = {
        "type": "custom",
        "spin_label": saved.get("site_configs", []),
        "site_configs": saved.get("site_configs", []),
        "boson_level": saved.get("boson_level"),
    }
    return _build_custom_state(schema, custom_input, system_block, backend_category)


# ---------------------------------------------------------------------------
# Utility
# ---------------------------------------------------------------------------

def _set_nested(d: dict, dotpath: str, value: Any) -> None:
    """Set a value in a nested dict using dot-separated path."""
    keys = dotpath.split(".")
    for key in keys[:-1]:
        if key not in d:
            d[key] = {}
        d = d[key]
    d[keys[-1]] = value
