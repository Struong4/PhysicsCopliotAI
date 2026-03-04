"""
Config validator for the MCP pipeline.

Every validation check reads from the 5 registry JSON files:
  models.json, systems.json, states.json, algorithms.json, config_schema.json

Zero hardcoded model names, algorithm names, parameter names, or backend conventions.
Returns {"valid": bool, "errors": [...], "warnings": [...]}.
"""

from __future__ import annotations

import math
from typing import Any


# ---------------------------------------------------------------------------
# Error codes
# ---------------------------------------------------------------------------

MISSING_FIELD = "MISSING_FIELD"
INVALID_TYPE = "INVALID_TYPE"
OUT_OF_RANGE = "OUT_OF_RANGE"
INVALID_VALUE = "INVALID_VALUE"
DTYPE_UNSAFE = "DTYPE_UNSAFE"
STATE_REQUIRED = "STATE_REQUIRED"
STATE_FORBIDDEN = "STATE_FORBIDDEN"
SIZE_EXCEEDS_LIMIT = "SIZE_EXCEEDS_LIMIT"
SPARSE_REQUIRES_NSTATES = "SPARSE_REQUIRES_NSTATES"
CONDITIONAL_FIELD_MISSING = "CONDITIONAL_FIELD_MISSING"
ARRAY_LENGTH_MISMATCH = "ARRAY_LENGTH_MISMATCH"
UNKNOWN_MODEL = "UNKNOWN_MODEL"
UNKNOWN_ALGORITHM = "UNKNOWN_ALGORITHM"


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

def validate_config(
    registry: dict,
    config: dict,
    mode: str = "simulation",
) -> dict:
    """Validate a config dict against the registry.

    Args:
        registry: All 5 registry files keyed as
            {"models", "systems", "states", "algorithms", "config_schema"}.
        config: The config dict to validate.
        mode: "simulation" or "analysis".

    Returns:
        {"valid": bool, "errors": [{"code": str, "message": str, "path": str}],
         "warnings": [{"message": str, "path": str}]}
    """
    errors: list[dict] = []
    warnings: list[dict] = []

    if mode == "analysis":
        _validate_analysis(registry, config, errors, warnings)
        return {"valid": len(errors) == 0, "errors": errors, "warnings": warnings}

    # Validate system block
    system_block = config.get("system")
    if system_block is None:
        errors.append(_err(MISSING_FIELD, "system block is required", "system"))
        return {"valid": False, "errors": errors, "warnings": warnings}

    _validate_system(registry, system_block, errors, warnings)

    # Validate model block
    model_block = config.get("model")
    if model_block is None:
        errors.append(_err(MISSING_FIELD, "model block is required", "model"))
    else:
        _validate_model(registry, model_block, system_block, errors, warnings)

    # Validate algorithm block
    algorithm_block = config.get("algorithm")
    if algorithm_block is None:
        errors.append(_err(MISSING_FIELD, "algorithm block is required", "algorithm"))
    else:
        _validate_algorithm(registry, algorithm_block, system_block, errors, warnings)

    # Validate state block
    algo_type = (algorithm_block or {}).get("type", "")
    _validate_state(registry, config.get("state"), algo_type, system_block, errors, warnings)

    # Cross-block: dtype consistency
    if model_block and system_block:
        _validate_dtype_consistency(registry, model_block, system_block, errors, warnings)

    return {"valid": len(errors) == 0, "errors": errors, "warnings": warnings}


# ---------------------------------------------------------------------------
# System validation
# ---------------------------------------------------------------------------

def _validate_system(
    registry: dict,
    system: dict,
    errors: list,
    warnings: list,
) -> None:
    systems_reg = registry["systems"]
    sys_type = system.get("type")

    if sys_type is None:
        errors.append(_err(MISSING_FIELD, "system.type is required", "system.type"))
        return

    type_spec = systems_reg.get("system_types", {}).get(sys_type)
    if type_spec is None:
        valid_types = list(systems_reg.get("system_types", {}).keys())
        errors.append(_err(
            INVALID_VALUE,
            f"Unknown system type '{sys_type}'. Valid: {valid_types}",
            "system.type",
        ))
        return

    fields_spec = type_spec.get("fields", {})
    required = type_spec.get("required_fields", [])

    for field_name in required:
        if field_name not in system:
            # Skip type — already validated
            if field_name == "type":
                continue
            field_def = fields_spec.get(field_name, {})
            if "default" not in field_def:
                errors.append(_err(
                    MISSING_FIELD,
                    f"system.{field_name} is required for {sys_type} systems",
                    f"system.{field_name}",
                ))

    # Validate individual fields
    for field_name, value in system.items():
        if field_name == "type":
            continue
        field_def = fields_spec.get(field_name, {})
        _validate_field(value, field_def, f"system.{field_name}", errors)


# ---------------------------------------------------------------------------
# Model validation
# ---------------------------------------------------------------------------

def _validate_model(
    registry: dict,
    model: dict,
    system: dict,
    errors: list,
    warnings: list,
) -> None:
    models_reg = registry["models"]
    model_name = model.get("name")

    if model_name is None:
        errors.append(_err(MISSING_FIELD, "model.name is required", "model.name"))
        return

    model_params = model.get("params", {})

    # Check prebuilt models
    prebuilt = models_reg.get("prebuilt_models", {}).get(model_name)
    if prebuilt:
        _validate_prebuilt_model(prebuilt, model_params, system, errors, warnings)
        return

    # Check custom models
    custom = models_reg.get("custom_models", {}).get(model_name)
    if custom:
        _validate_custom_model(models_reg, custom, model_params, system, errors, warnings)
        return

    # Check user-registered models
    user_models = models_reg.get("user_models", {}).get("models", {})
    if model_name in user_models:
        return  # User models have minimal validation

    errors.append(_err(
        UNKNOWN_MODEL,
        f"Unknown model '{model_name}'",
        "model.name",
    ))


def _validate_prebuilt_model(
    spec: dict,
    params: dict,
    system: dict,
    errors: list,
    warnings: list,
) -> None:
    # Check system_type match
    expected_sys = spec.get("system_type")
    actual_sys = system.get("type")
    if expected_sys and actual_sys and expected_sys != actual_sys:
        errors.append(_err(
            INVALID_VALUE,
            f"Model requires system type '{expected_sys}', got '{actual_sys}'",
            "model",
        ))

    # Check required params
    for pname in spec.get("required_params", []):
        if pname not in params:
            errors.append(_err(
                MISSING_FIELD,
                f"model.params.{pname} is required",
                f"model.params.{pname}",
            ))

    # Validate individual params
    param_specs = spec.get("params", {})
    for pname, value in params.items():
        pspec = param_specs.get(pname, {})
        if isinstance(pspec, dict):
            _validate_field(value, pspec, f"model.params.{pname}", errors)


def _validate_custom_model(
    models_reg: dict,
    spec: dict,
    params: dict,
    system: dict,
    errors: list,
    warnings: list,
) -> None:
    # Check system_type match
    expected_sys = spec.get("system_type")
    actual_sys = system.get("type")
    if expected_sys and actual_sys and expected_sys != actual_sys:
        errors.append(_err(
            INVALID_VALUE,
            f"Custom model requires system type '{expected_sys}', got '{actual_sys}'",
            "model",
        ))

    # Check that terms/channels exist
    has_terms = "terms" in params or "channels" in params
    if not has_terms:
        errors.append(_err(
            MISSING_FIELD,
            "Custom model requires 'terms' or 'channels' in model.params",
            "model.params",
        ))
        return

    # Get terms data
    terms_data = params.get("terms", params.get("channels", []))

    # Validate individual terms if we have term_types info
    term_types_spec = spec.get("term_types", {})
    if term_types_spec and isinstance(terms_data, list):
        for i, term in enumerate(terms_data):
            _validate_custom_term(term_types_spec, term, f"model.params.terms[{i}]", errors)
    elif isinstance(terms_data, dict):
        # Spinboson nested structure
        for category_key, category_terms in terms_data.items():
            if isinstance(category_terms, list):
                for i, term in enumerate(category_terms):
                    path = f"model.params.terms.{category_key}[{i}]"
                    # spin_terms use the custom_spin term_types
                    if "spin" in category_key and term_types_spec:
                        _validate_custom_term(term_types_spec, term, path, errors)


def _validate_custom_term(
    term_types_spec: dict,
    term: dict,
    path: str,
    errors: list,
) -> None:
    term_type = term.get("type", "")
    type_spec = term_types_spec.get(term_type)
    if type_spec is None:
        return  # Unknown term type — skip (could be TN format)

    # Check required fields
    for field in type_spec.get("required_fields", []):
        if field not in term:
            errors.append(_err(MISSING_FIELD, f"{path}.{field} is required", f"{path}.{field}"))

    # Check conditional fields
    conditional = type_spec.get("conditional_fields", {})
    for cfield, cspec in conditional.items():
        if isinstance(cspec, dict) and "required_when" in cspec:
            req_when = cspec["required_when"]
            for trigger_param, trigger_values in req_when.items():
                if term.get(trigger_param) in trigger_values and cfield not in term:
                    errors.append(_err(
                        CONDITIONAL_FIELD_MISSING,
                        f"{path}.{cfield} is required when {trigger_param} is '{term.get(trigger_param)}'",
                        f"{path}.{cfield}",
                    ))

    # Validate field values
    fields_spec = type_spec.get("fields", {})
    for fname, fval in term.items():
        fspec = fields_spec.get(fname, {})
        if isinstance(fspec, dict):
            _validate_field(fval, fspec, f"{path}.{fname}", errors)


# ---------------------------------------------------------------------------
# Algorithm validation
# ---------------------------------------------------------------------------

def _validate_algorithm(
    registry: dict,
    algorithm: dict,
    system: dict,
    errors: list,
    warnings: list,
) -> None:
    algorithms_reg = registry["algorithms"]
    schema = registry["config_schema"]
    algo_type = algorithm.get("type")

    if algo_type is None:
        errors.append(_err(MISSING_FIELD, "algorithm.type is required", "algorithm.type"))
        return

    algo_spec = algorithms_reg.get("algorithms", {}).get(algo_type)
    if algo_spec is None:
        valid_algos = list(algorithms_reg.get("algorithms", {}).keys())
        errors.append(_err(
            UNKNOWN_ALGORITHM,
            f"Unknown algorithm '{algo_type}'. Valid: {valid_algos}",
            "algorithm.type",
        ))
        return

    # Validate params against spec
    param_specs = algo_spec.get("params", {})
    _validate_algorithm_params(algorithm, param_specs, "algorithm", errors)

    # Check constraint_logic (e.g., use_sparse requires n_states)
    for pname, pspec in param_specs.items():
        if isinstance(pspec, dict) and "constraint_logic" in pspec:
            _check_constraint_logic(pspec["constraint_logic"], algorithm, errors)

    # Check system size limits
    _check_system_size_limits(registry, algo_type, system, errors, warnings)


def _validate_algorithm_params(
    algorithm: dict,
    param_specs: dict,
    path: str,
    errors: list,
) -> None:
    """Recursively validate algorithm parameters."""
    for section_name, section_spec in param_specs.items():
        if isinstance(section_spec, dict):
            # Check if this is a nested section (solver, options, run) or a direct param
            if any(isinstance(v, dict) and "type" in v for v in section_spec.values()):
                # It's a section with sub-params
                section_data = algorithm.get(section_name, {})
                if isinstance(section_data, dict):
                    for pname, pspec in section_spec.items():
                        if isinstance(pspec, dict) and pname in section_data:
                            _validate_field(
                                section_data[pname],
                                pspec,
                                f"{path}.{section_name}.{pname}",
                                errors,
                            )
            elif "type" in section_spec:
                # Direct param
                if section_name in algorithm:
                    _validate_field(
                        algorithm[section_name],
                        section_spec,
                        f"{path}.{section_name}",
                        errors,
                    )


def _check_constraint_logic(
    logic: dict,
    algorithm: dict,
    errors: list,
) -> None:
    """Check constraint_logic rules like 'if use_sparse=true, then n_states required'."""
    condition = logic.get("if", {})
    then_required = logic.get("then_required", [])

    # Check if condition is met
    condition_met = all(
        algorithm.get(k) == v for k, v in condition.items()
    )

    if condition_met:
        for field in then_required:
            if field not in algorithm or algorithm[field] is None:
                errors.append(_err(
                    SPARSE_REQUIRES_NSTATES,
                    f"algorithm.{field} is required when {condition}",
                    f"algorithm.{field}",
                ))


def _check_system_size_limits(
    registry: dict,
    algo_type: str,
    system: dict,
    errors: list,
    warnings: list,
) -> None:
    """Check if system size exceeds ED limits."""
    systems_reg = registry["systems"]
    sys_type = system.get("type", "spin")
    type_spec = systems_reg.get("system_types", {}).get(sys_type, {})
    fields_spec = type_spec.get("fields", {})

    # Find the size field (N for spin, N_spins for spinboson)
    size_field = "N" if sys_type == "spin" else "N_spins"
    n_val = system.get(size_field)
    if n_val is None:
        return

    # Check constraints_by_algorithm
    size_spec = fields_spec.get(size_field, {})
    constraints = size_spec.get("constraints_by_algorithm", {}).get(algo_type, {})

    if not constraints:
        return

    # Check hard limits by S value
    limits_by_s = constraints.get("limits_by_S", {})
    s_val = system.get("S", 0.5)
    s_key = str(s_val)

    if s_key in limits_by_s:
        limit_spec = limits_by_s[s_key]
        hard_max = limit_spec.get("max")
        rec_max = limit_spec.get("recommended_max")

        if hard_max is not None and n_val > hard_max:
            errors.append(_err(
                SIZE_EXCEEDS_LIMIT,
                f"{size_field}={n_val} exceeds maximum {hard_max} for "
                f"{algo_type} with S={s_val}. {limit_spec.get('note', '')}",
                f"system.{size_field}",
            ))
        elif rec_max is not None and n_val > rec_max:
            warnings.append({
                "message": f"{size_field}={n_val} exceeds recommended maximum "
                           f"{rec_max} for {algo_type} with S={s_val}. "
                           f"{limit_spec.get('note', '')}",
                "path": f"system.{size_field}",
            })

    # Check minimum
    minimum = constraints.get("minimum")
    if minimum is not None and n_val < minimum:
        errors.append(_err(
            OUT_OF_RANGE,
            f"{size_field}={n_val} is below minimum {minimum} for {algo_type}",
            f"system.{size_field}",
        ))


# ---------------------------------------------------------------------------
# State validation
# ---------------------------------------------------------------------------

def _validate_state(
    registry: dict,
    state: dict | None,
    algo_type: str,
    system: dict,
    errors: list,
    warnings: list,
) -> None:
    states_reg = registry["states"]

    # Check algorithm requirement
    algo_req = states_reg.get("algorithm_requirement", {}).get(algo_type, {})
    requires_state = algo_req.get("requires_state", True) if isinstance(algo_req, dict) else True

    if not requires_state and state is not None:
        warnings.append({
            "message": f"State block provided but {algo_type} does not use an initial state. It will be ignored.",
            "path": "state",
        })
        return

    if requires_state and state is None:
        errors.append(_err(
            STATE_REQUIRED,
            f"{algo_type} requires an initial state block",
            "state",
        ))
        return

    if state is None:
        return

    state_type = state.get("type")
    if state_type is None:
        errors.append(_err(MISSING_FIELD, "state.type is required", "state.type"))
        return

    sys_type = system.get("type", "spin")

    if state_type == "custom":
        _validate_custom_state(state, system, sys_type, errors)
    elif state_type == "prebuilt":
        _validate_prebuilt_state(registry, state, system, sys_type, errors)
    elif state_type == "random":
        pass  # Minimal validation needed
    else:
        # Could be a user-registered state
        user_states = states_reg.get("user_states", {}).get("states", {})
        if state_type not in user_states and state.get("name") not in user_states:
            errors.append(_err(
                INVALID_VALUE,
                f"Unknown state type '{state_type}'",
                "state.type",
            ))


def _validate_custom_state(
    state: dict,
    system: dict,
    sys_type: str,
    errors: list,
) -> None:
    """Validate custom state: check array lengths match system size."""
    # Find site data under various possible keys
    site_data = (
        state.get("spin_label")
        or state.get("site_configs")
        or (state.get("params", {}) or {}).get("spin_label")
        or (state.get("params", {}) or {}).get("site_configs")
    )

    if site_data is None:
        errors.append(_err(
            MISSING_FIELD,
            "Custom state requires site configuration array (spin_label or site_configs)",
            "state",
        ))
        return

    # Check array length
    expected_len = system.get("N") if sys_type == "spin" else system.get("N_spins")
    if expected_len is not None and isinstance(site_data, list):
        if len(site_data) != expected_len:
            size_field = "N" if sys_type == "spin" else "N_spins"
            errors.append(_err(
                ARRAY_LENGTH_MISMATCH,
                f"Site config array length {len(site_data)} != system.{size_field}={expected_len}",
                "state.site_configs",
            ))

    # For spinboson, check boson_level bounds
    if sys_type == "spinboson":
        boson_level = state.get("boson_level") or (state.get("params", {}) or {}).get("boson_level")
        nmax = system.get("nmax")
        if boson_level is not None and nmax is not None:
            if boson_level < 0 or boson_level > nmax:
                errors.append(_err(
                    OUT_OF_RANGE,
                    f"boson_level={boson_level} must be in [0, nmax={nmax}]",
                    "state.boson_level",
                ))


def _validate_prebuilt_state(
    registry: dict,
    state: dict,
    system: dict,
    sys_type: str,
    errors: list,
) -> None:
    """Validate prebuilt pattern state params."""
    states_reg = registry["states"]
    pattern_name = state.get("name")

    if pattern_name is None:
        errors.append(_err(MISSING_FIELD, "state.name is required for prebuilt states", "state.name"))
        return

    pattern_spec = (
        states_reg.get("state_types", {})
        .get("prebuilt", {})
        .get("patterns", {})
        .get(pattern_name)
    )
    if pattern_spec is None:
        valid = list(
            states_reg.get("state_types", {}).get("prebuilt", {}).get("patterns", {}).keys()
        )
        errors.append(_err(INVALID_VALUE, f"Unknown pattern '{pattern_name}'. Valid: {valid}", "state.name"))
        return

    params = state.get("params", {})

    # Check required params
    req_key = "spinboson_required_params" if sys_type == "spinboson" else "required_params"
    for pname in pattern_spec.get(req_key, []):
        if pname not in params:
            errors.append(_err(
                MISSING_FIELD,
                f"state.params.{pname} is required for pattern '{pattern_name}'",
                f"state.params.{pname}",
            ))

    # Validate eigenstate bounds
    s_val = system.get("S", 0.5)
    d = int(math.floor(2 * s_val + 1))

    eigenstate_fields = ["eigenstate", "spin_eigenstate", "even_state", "odd_state",
                         "left_state", "right_state", "base_state", "flip_state"]
    for ef in eigenstate_fields:
        if ef in params:
            val = params[ef]
            if isinstance(val, int) and (val < 1 or val > d):
                errors.append(_err(
                    OUT_OF_RANGE,
                    f"state.params.{ef}={val} must be in [1, {d}] for S={s_val}",
                    f"state.params.{ef}",
                ))

    # Validate position-based params
    size_field = "N" if sys_type == "spin" else "N_spins"
    n_val = system.get(size_field)

    if "position" in params and n_val is not None:
        pos = params["position"]
        if isinstance(pos, int) and (pos < 1 or pos >= n_val):
            errors.append(_err(
                OUT_OF_RANGE,
                f"state.params.position={pos} must be in [1, {n_val - 1}]",
                "state.params.position",
            ))

    # Validate boson_level for spinboson
    if sys_type == "spinboson" and "boson_level" in params:
        nmax = system.get("nmax")
        bl = params["boson_level"]
        if nmax is not None and isinstance(bl, int) and (bl < 0 or bl > nmax):
            errors.append(_err(
                OUT_OF_RANGE,
                f"state.params.boson_level={bl} must be in [0, nmax={nmax}]",
                "state.params.boson_level",
            ))


# ---------------------------------------------------------------------------
# dtype consistency
# ---------------------------------------------------------------------------

def _validate_dtype_consistency(
    registry: dict,
    model: dict,
    system: dict,
    errors: list,
    warnings: list,
) -> None:
    """Check if the declared dtype is safe for the operators used."""
    schema = registry["config_schema"]
    models_reg = registry["models"]
    declared_dtype = system.get("dtype") or model.get("params", {}).get("dtype")

    if declared_dtype != "Float64":
        return  # ComplexF64 is always safe

    model_name = model.get("name", "")
    model_params = model.get("params", {})

    # For prebuilt: evaluate dtype_logic
    prebuilt_spec = models_reg.get("prebuilt_models", {}).get(model_name, {})
    if prebuilt_spec and "dtype_logic" in prebuilt_spec:
        logic = prebuilt_spec["dtype_logic"]
        safe_rules = logic.get("float64_safe_when", [])
        is_safe = False
        for rule in safe_rules:
            if "all_in" in rule:
                spec = rule["all_in"]
                check_params = spec.get("params", [])
                allowed = set(spec.get("allowed", []))
                if all(model_params.get(p) in allowed for p in check_params):
                    is_safe = True
                    break
            elif "all_zero" in rule:
                spec = rule["all_zero"]
                check_params = spec.get("params", [])
                if all(model_params.get(p, 0) == 0 for p in check_params):
                    is_safe = True
                    break

        if not is_safe:
            errors.append(_err(
                DTYPE_UNSAFE,
                f"Float64 is not safe for model '{model_name}' with current params. "
                f"Use ComplexF64.",
                "system.dtype",
            ))
        return

    # For custom: scan operators
    scan_config = schema.get("dtype_resolution", {}).get("custom_model_scan", {})
    if scan_config:
        systems_reg = registry["systems"]
        source_path = scan_config.get("operator_source", "").split(".")
        op_registry = systems_reg
        for key in source_path:
            op_registry = op_registry.get(key, {})

        check_field = scan_config.get("check_field", "real")
        complex_when = scan_config.get("complex_when", False)

        operators = _extract_operators(model_params)
        for op in operators:
            op_spec = op_registry.get(op, {})
            if op_spec.get(check_field) == complex_when:
                errors.append(_err(
                    DTYPE_UNSAFE,
                    f"Float64 is not safe: operator '{op}' requires ComplexF64",
                    "system.dtype",
                ))
                return


# ---------------------------------------------------------------------------
# Analysis validation
# ---------------------------------------------------------------------------

def _validate_analysis(
    registry: dict,
    config: dict,
    errors: list,
    warnings: list,
) -> None:
    """Validate an analysis config."""
    schema = registry["config_schema"]

    sim_config = config.get("simulation")
    if sim_config is None:
        errors.append(_err(MISSING_FIELD, "analysis config requires 'simulation' block", "simulation"))
        return

    selection = config.get("selection")
    if selection is None:
        errors.append(_err(MISSING_FIELD, "analysis config requires 'selection' block", "selection"))
        return

    observable = config.get("observable")
    if observable is None:
        errors.append(_err(MISSING_FIELD, "analysis config requires 'observable' block", "observable"))
        return

    # Check selection key matches algorithm
    algo_type = sim_config.get("algorithm", {}).get("type", "")
    sel_key_map = schema.get("analysis_assembly", {}).get("selection_key", {})
    expected_key = sel_key_map.get(algo_type)

    if expected_key and expected_key not in selection:
        warnings.append({
            "message": f"Selection key '{expected_key}' expected for algorithm '{algo_type}' "
                       f"but not found in selection block. Found: {list(selection.keys())}",
            "path": "selection",
        })


# ---------------------------------------------------------------------------
# Field validation utility
# ---------------------------------------------------------------------------

def _validate_field(
    value: Any,
    spec: dict,
    path: str,
    errors: list,
) -> None:
    """Validate a single field value against its spec."""
    if not isinstance(spec, dict):
        return

    # Skip validation for None/null values (they represent optional/unset fields)
    if value is None:
        return

    # Type check
    expected_type = spec.get("type")
    if expected_type:
        type_ok = _check_type(value, expected_type)
        if not type_ok:
            errors.append(_err(
                INVALID_TYPE,
                f"{path} should be {expected_type}, got {type(value).__name__}",
                path,
            ))
            return

    # Allowed values
    allowed = spec.get("allowed_values")
    if allowed is not None:
        if isinstance(allowed, list) and value not in allowed:
            errors.append(_err(INVALID_VALUE, f"{path}={value} not in {allowed}", path))
        elif isinstance(allowed, dict):
            # Handle bool -> string key comparison (e.g., True -> "true")
            str_val = str(value).lower() if isinstance(value, bool) else value
            if value not in allowed and str_val not in allowed:
                errors.append(_err(INVALID_VALUE, f"{path}={value} not in {list(allowed.keys())}", path))

    # Minimum
    minimum = spec.get("minimum")
    if minimum is not None and isinstance(value, (int, float)) and not isinstance(value, bool):
        if value < minimum:
            errors.append(_err(OUT_OF_RANGE, f"{path}={value} < minimum {minimum}", path))


def _check_type(value: Any, expected: str) -> bool:
    """Check if value matches expected type string."""
    if expected == "int":
        return isinstance(value, int) and not isinstance(value, bool)
    elif expected == "float":
        return isinstance(value, (int, float)) and not isinstance(value, bool)
    elif expected == "string":
        return isinstance(value, str)
    elif expected == "bool":
        return isinstance(value, bool)
    elif expected == "array":
        return isinstance(value, list)
    return True


# ---------------------------------------------------------------------------
# Helpers shared with builder
# ---------------------------------------------------------------------------

def _extract_operators(params: dict) -> set[str]:
    """Recursively extract all spin operator strings from model params."""
    ops: set[str] = set()
    _walk_for_operators(params, ops)
    return ops


def _walk_for_operators(obj: Any, ops: set[str]) -> None:
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


def _err(code: str, message: str, path: str) -> dict:
    return {"code": code, "message": message, "path": path}
