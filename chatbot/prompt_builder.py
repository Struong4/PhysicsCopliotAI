"""
Build the SYSTEM_PROMPT dynamically from registry data and keywords.yaml.

Sections generated from the registry (single source of truth):
  - Algorithm selection guide  <- systems.json + algorithms.json
  - System block               <- systems.json (spin and spinboson)
  - Models block               <- models.json (all prebuilt models)
  - Algorithms block           <- algorithms.json (all 4 algorithms)
  - States block               <- states.json (ED and TN variants)

Sections kept static (not registry-owned):
  - Role description
  - Conversation rules (task routing pulled from keywords.yaml)
  - General questions section
  - Result interpretation section
"""

import json

# combines all the sections for a prompt to send to the LLM
def build_system_prompt(registries: dict, keywords: dict) -> str:
    models_reg = registries["models"]
    algo_reg = registries["algorithms"]
    states_reg = registries["states"]
    systems_reg = registries["systems"]

    sections = [
        _role_section(),
        _algorithm_selection_section(systems_reg, algo_reg),
        _config_structure_section(systems_reg, models_reg, algo_reg, states_reg),
        _conversation_rules_section(keywords),
        _physics_vocabulary_section(keywords),
        _general_questions_section(models_reg),
        _result_interpretation_section(),
        _catalog_section(),
        _observable_tools_section(),
    ]
    return "\n\n".join(sections)


# -- Static sections --

def _role_section() -> str:
    return (
        "You are a simulation assistant for TNCodebase, a quantum physics framework.\n"
        "Your job is to help users configure and run quantum many-body simulations\n"
        "by asking questions and building a JSON configuration for them.\n"
        "You support four algorithms: dmrg, tdvp, ed_spectrum, and ed_time_evolution."
    )

# just telling the LLM to provide insight on simulation after done running
def _result_interpretation_section() -> str:
    return (
        "=== INTERPRETING SIMULATION RESULTS ===\n"
        'When a message begins with "[OBSERVABLE RESULT]", an observable calculation has\n'
        "just completed. Interpret the result for the user in plain English:\n"
        "  * Mention the observable type and what it measures physically.\n"
        "  * Comment on the mean, final value, and trend (increasing/decreasing/oscillating).\n"
        "  * Relate the result to the physics: e.g. for entanglement_entropy comment on\n"
        "    area law vs. volume law; for energy_expectation comment on convergence;\n"
        "    for correlation_function comment on decay behavior.\n"
        "  * Suggest follow-up observables or parameter changes if relevant.\n"
        "After interpreting, stay ready for follow-up. Do NOT call any tools in response.\n\n"
        'When a message begins with "[SIMULATION RESULT]", the Julia pipeline has\n'
        "just completed a run. Interpret it for the user in plain English:\n"
        "  * For ed_spectrum: comment on what the energy spectrum implies about the\n"
        "    phase (gapped vs. gapless), and invite follow-up questions.\n"
        "  * For ed_time_evolution: acknowledge the run and invite the user to ask\n"
        "    about observable calculations or to re-run with different parameters.\n"
        "  * For dmrg: comment on the ground state energy found and invite the user\n"
        "    to ask about observables or convergence.\n"
        "  * For tdvp: acknowledge the time evolution run and invite observable\n"
        "    calculations or parameter changes.\n"
        "  * If deduplicated=true, explain that an identical simulation already\n"
        "    existed in the catalog so no recomputation was needed.\n"
        "After interpreting, stay ready for follow-up questions or a new simulation\n"
        "request. Do NOT call submit_config in response to a result message."
    )


# -- Registry-driven sections --

# reads from system and algorithm.json the info it needs to make sure the config is set up correctly (verification)
def _algorithm_selection_section(systems: dict, algorithms: dict) -> str:
    spin = systems["system_types"]["spin"]
    ed_limits = spin["fields"]["N"]["constraints_by_algorithm"]["ed_spectrum"]["limits_by_S"]
    max_n_ed = ed_limits["0.5"]["max"]
    sel = algorithms.get("algorithm_selection_guide", {}).get("rules", {})

    lines = [
        "=== ALGORITHM SELECTION ===",
        "Choose algorithm based on system size and task:",
        f"  Ground state, N <= {max_n_ed} (spin-1/2): ed_spectrum  (exact, full spectrum)",
        "  Ground state, N > 14:             dmrg         (approximate, scales to N~1000)",
        f"  Dynamics,     N <= {max_n_ed} (spin-1/2): ed_time_evolution (exact)",
        "  Dynamics,     N > 14:             tdvp         (approximate, real-time MPS evolution)",
        "",
        "ED (Exact Diagonalization): numerically exact, hard limit N <= 14 for spin-1/2.",
        "TN (Tensor Networks):       approximate via MPS, chi_max controls accuracy, no size limit.",
        "  Key TN params: chi_max (bond dimension, higher = more accurate), local_dim = floor(2*S+1).",
    ]
    return "\n".join(lines)


# organizes the state, model, algorithm, and system for the config
def _config_structure_section(systems, models, algorithms, states) -> str:
    header = (
        "=== CONFIG STRUCTURE ===\n"
        "Every config has four top-level keys: system, model, algorithm, state.\n"
        "(ed_spectrum does not need a state block.)"
    )
    return "\n\n".join([
        header,
        _system_block(systems),
        _models_block(models),
        _algorithms_block(algorithms),
        _states_block(states),
    ])

# reads defaults from system to build the system block 
def _system_block(systems: dict) -> str:
    spin = systems["system_types"]["spin"]
    sb = systems["system_types"]["spinboson"]
    d_dtype = spin["fields"]["dtype"]["default"]
    d_s = spin["fields"]["S"]["default"]
    d_nmax = sb["fields"]["nmax"]["default"]

    return (
        "-- SYSTEM --\n"
        "\n"
        "Spin system (transverse_field_ising, heisenberg, long_range_ising):\n"
        "{\n"
        '  "system": {\n'
        '    "type": "spin",\n'
        '    "N": <int>,          (no limit for dmrg/tdvp; <= 14 for ED spin-1/2)\n'
        f'    "S": {d_s},              (default, don\'t ask unless user specifies)\n'
        f'    "dtype": "{d_dtype}"   (always use this default)\n'
        "  }\n"
        "}\n"
        "\n"
        "Spin-boson system (ising_dicke, long_range_ising_dicke):\n"
        "{\n"
        '  "system": {\n'
        '    "type": "spinboson",\n'
        '    "N_spins": <int>,    (number of spin sites, not counting the boson site)\n'
        f'    "nmax": {d_nmax},            (boson Fock cutoff, default {d_nmax})\n'
        f'    "S": {d_s},\n'
        f'    "dtype": "{d_dtype}"\n'
        "  }\n"
        "}"
    )


def _models_block(models: dict) -> str:
    lines = [
        "-- MODELS --",
        "",
        'CRITICAL: The model block MUST use "name" (not "type") and ALL params MUST be nested under "params".',
        "",
    ]

    for name, entry in models["prebuilt_models"].items():
        sys_type = entry.get("system_type", "spin")
        hamiltonian = entry.get("hamiltonian", name)
        example_params = (
            entry.get("example_config", {}).get("model", {}).get("params", {})
        )
        params_meta = entry.get("params", {})
        note = entry.get("note", "")
        tn_only = entry.get("tn_only_params", [])

        model_json = json.dumps(
            {"model": {"name": name, "params": example_params}}, indent=2
        )

        tn_note = "  (TN: also add \"N\": <system.N> to params)" if not tn_only else ""
        lines.append(f"{name}  [system_type: {sys_type}]{tn_note}")
        lines.append(f"  {hamiltonian}")
        lines.append(model_json)

        for p, meta in params_meta.items():
            if meta.get("type") == "string" and "allowed_values" in meta:
                allowed = meta["allowed_values"]
                lines.append(f'  {p}: one of [{", ".join(allowed)}]')

        if tn_only:
            lines.append(f"  Note: {note}")

        lines.append("")

    user_models = models.get("user_models", {}).get("models", {})
    if user_models:
        lines.append("User-registered models (also available):")
        for uname, uentry in user_models.items():
            desc = uentry.get("description", "no description")
            lines.append(f"  {uname} - {desc}")
        lines.append("")

    return "\n".join(lines)


def _algorithms_block(algorithms: dict) -> str:
    lines = ["-- ALGORITHMS --", ""]

    for name, entry in algorithms["algorithms"].items():
        desc = entry.get("description", "")
        short_desc = desc.split(".")[0] if desc else name
        params = entry.get("params", {})

        lines.append(f"{name} - {short_desc}:")

        example = entry.get("example_config") or next(
            iter(entry.get("example_configs", {}).values()), {}
        )
        lines.append(json.dumps(example, indent=2))

        # Surface important per-param notes
        for p_name, p_meta in params.items():
            if isinstance(p_meta, dict):
                constraint = p_meta.get("constraint", "")
                required = p_meta.get("required", True)
                default = p_meta.get("default")
                if not required and default is None:
                    lines.append(
                        f'  Optional: "{p_name}": <{p_meta.get("type", "value")}>'
                        f'  ({p_meta.get("description", "")})'
                    )
                if constraint:
                    lines.append(f"  Constraint: {constraint}")
            elif isinstance(p_meta, dict):
                # nested param group (solver, options, run)
                for sub_name, sub_meta in p_meta.items():
                    if isinstance(sub_meta, dict):
                        constraint = sub_meta.get("constraint", "")
                        if constraint:
                            lines.append(f"  Constraint ({p_name}.{sub_name}): {constraint}")

        lines.append("")

    # Add the local_dim note since it applies to both dmrg and tdvp
    note = algorithms.get("local_dim_note", {})
    if note:
        formula = note.get("formula", "local_dim = floor(2 * S + 1)")
        lines.append(f"NOTE: {formula}  (e.g. S=0.5 -> local_dim=2). Set this in options for dmrg/tdvp.")

    return "\n".join(lines)


def _states_block(states: dict) -> str:
    lines = ["-- STATES --", ""]

    state_types = states["state_types"]

    # Random - show both ED and TN variants
    random_st = state_types["random"]
    ex_ed = random_st.get("example_config_ed", {"state": {"type": "random"}})
    ex_tn = random_st.get("example_config_tn", {"state": {"type": "random", "params": {"bond_dim": 10}}})
    lines.append("Random state (ED - ed_time_evolution):")
    lines.append(json.dumps(ex_ed, indent=2))
    lines.append("")
    lines.append("Random state (TN - dmrg/tdvp, requires bond_dim):")
    lines.append(json.dumps(ex_tn, indent=2))
    lines.append("")

    # Prebuilt patterns - same config for both ED and TN
    prebuilt = state_types["prebuilt"]
    lines.append("Prebuilt patterns (same structure for ED and TN):")
    lines.append("")
    for pname, pattern in prebuilt.get("patterns", {}).items():
        display = pattern.get("display_name", pname)
        ex_spin = pattern.get("example_config_spin", {})
        req = pattern.get("required_params", [])

        lines.append(f"  {display}:")
        lines.append(json.dumps(ex_spin, indent=2))
        if req:
            lines.append(f"  Required: {req}")
        lines.append("")

    # Algorithm requirement table
    algo_req = states.get("algorithm_requirement", {})
    if algo_req:
        lines.append("State block requirement by algorithm:")
        for algo, rule in algo_req.items():
            if isinstance(rule, dict):
                desc = rule.get("description", "")
                lines.append(f"  {algo}: {desc}")
            else:
                lines.append(f"  {algo}: {rule}")

    return "\n".join(lines)


# -- Keywords-driven section --

# tells LLM how to treat conversation, so it trains the LLM to make sure it knows what to do
def _conversation_rules_section(keywords: dict) -> str:
    lines = [
        "=== CONVERSATION RULES ===",
        "1. Be efficient: ask ALL missing required info in ONE message, then generate the config.",
        "   Do not ask questions one at a time. Do not ask for things the user already stated.",
        "2. Use defaults silently without asking: chi_max=64, n_sweeps=20, krylov_dim=30,",
        "   bond_dim=10, evol_type=real. Only ask if the user explicitly wants to customize.",
        "3. Required from user - ed_spectrum: model, N.",
        "   Required from user - ed_time_evolution: model, N, dt, total_time.",
        "   Required from user - dmrg: model, N.",
        "   Required from user - tdvp: model, N, dt, total_time.",
        "   Required from user - long_range_ising only: also ask alpha and n_exp.",
        "4. When you have all required info, immediately call submit_config. Do NOT show raw JSON.",
        "5. After proposing a config, if the user asks for changes, call submit_config again.",
        "",
        "Algorithm-specific rules:",
        "  * ed_spectrum: NO state block. use_sparse=false for N<=12, use_sparse=true for N=13 or 14.",
        "  * ed_time_evolution: requires state. dt controls output resolution, not accuracy.",
        "  * dmrg/tdvp: include 'N' in model params equal to system.N (do NOT ask the user for this).",
        "  * ed_spectrum/ed_time_evolution: do NOT include 'N' in model params.",
        "  * dmrg: requires state with bond_dim=10. local_dim=floor(2*S+1). chi_max=64, n_sweeps=20.",
        "  * tdvp: requires state with bond_dim=10. local_dim=floor(2*S+1). evol_type=real.",
        "    n_sweeps = total_time / dt. chi_max=64, krylov_dim=30.",
        "  * For TFIM and long_range_ising: default coupling_dir=Z and field_dir=X unless user says otherwise.",
        "  * For quench dynamics (ed_time_evolution or tdvp), default initial state to",
        "    polarized eigenstate=2 (all spins up) unless user specifies otherwise.",
        "  * long_range_ising with TN (dmrg/tdvp): n_exp is a required model param (ask for it).",
        "    N is also required for TN but do NOT ask the user - use system.N.",
        "  * long_range_ising with ED: n_exp and N must be OMITTED from model params.",
    ]

    task_routing = keywords.get("task_routing", {})
    if task_routing:
        lines += ["", "Task routing (infer algorithm from user phrasing):"]
        for task_key, entry in task_routing.items():
            phrases = entry.get("phrases", []) if isinstance(entry, dict) else entry
            sample = ", ".join(f'"{t}"' for t in phrases[:4])
            target = entry.get("task_key", task_key) if isinstance(entry, dict) else task_key
            lines.append(f"  {sample} -> {target}")

    algo_vocab = keywords.get("algorithm_vocabulary", {})
    if algo_vocab:
        lines += ["", "Algorithm name recognition (user explicitly names an algorithm):"]
        for _, entry in algo_vocab.items():
            phrases = entry.get("phrases", [])
            sample = ", ".join(f'"{t}"' for t in phrases[:4])
            algorithm = entry.get("algorithm", "")
            lines.append(f"  {sample} -> {algorithm}")

    return "\n".join(lines)


def _physics_vocabulary_section(keywords: dict) -> str:
    lines = ["=== PHYSICS VOCABULARY ==="]

    # System detection
    sys_det = keywords.get("system_detection", {})
    if sys_det:
        lines += ["", "System type recognition (map user language to system type):"]
        for sys_key, entry in sys_det.items():
            phrases = entry.get("phrases", [])
            sample = ", ".join(f'"{p}"' for p in phrases[:5])
            lines.append(f"  {sample} -> system.type = \"{sys_key}\"")

    # Physics vocabulary (ferromagnetic, XXZ, critical point, etc.)
    phys_vocab = keywords.get("physics_vocabulary", {})
    if phys_vocab:
        lines += ["", "Physics term → parameter implications (apply silently when user uses these terms):"]
        for term, entry in phys_vocab.items():
            desc = entry.get("description", "")
            implies = entry.get("implies", {})
            model = entry.get("model", "")
            implies_str = ", ".join(f"{k}={v}" for k, v in implies.items()) if implies else ""
            model_str = f" [model: {model}]" if model else ""
            lines.append(f"  \"{term}\": {desc}{model_str}")
            if implies_str:
                lines.append(f"    → implies: {implies_str}")

    # Operator vocabulary (magnetization → Z, etc.)
    op_vocab = keywords.get("operator_vocabulary", {})
    if op_vocab:
        lines += ["", "Operator name recognition (map physics terms to operator codes):"]
        for term, entry in op_vocab.items():
            op = entry.get("operator", "")
            desc = entry.get("description", "")
            lines.append(f"  \"{term}\" → operator: \"{op}\"  ({desc})")

    # Observable vocabulary
    obs_vocab = keywords.get("observable_vocabulary", {})
    if obs_vocab:
        lines += ["", "Observable recognition (map user phrases to observable_type):"]
        for obs_key, entry in obs_vocab.items():
            phrases = entry.get("phrases", [])
            obs_type = entry.get("observable_type", obs_key)
            sample = ", ".join(f'"{p}"' for p in phrases[:4])
            lines.append(f"  {sample} -> observable_type: \"{obs_type}\"")

    # State vocabulary
    state_vocab = keywords.get("state_vocabulary", {})
    if state_vocab:
        lines += ["", "State recognition (map user descriptions to state configs):"]
        for term, entry in state_vocab.items():
            desc = entry.get("description", "")
            state_type = entry.get("state_type", "")
            state_name = entry.get("state_name", "")
            params = entry.get("params", {})
            applies = entry.get("applies_to", "")
            config_str = f"type={state_type}"
            if state_name:
                config_str += f", name={state_name}"
            if params:
                config_str += f", params={params}"
            if applies:
                config_str += f" [{applies} only]"
            lines.append(f"  \"{term}\": {desc}")
            lines.append(f"    → {config_str}")

    # Selection vocabulary
    sel_vocab = keywords.get("selection_vocabulary", {})
    if sel_vocab:
        lines += ["", "Selection mode recognition (map sweep/step selection phrases):"]
        for mode_key, entry in sel_vocab.items():
            phrases = entry.get("phrases", [])
            mode = entry.get("mode", mode_key)
            sample = ", ".join(f'"{p}"' for p in phrases[:4])
            lines.append(f"  {sample} -> selection: \"{mode}\"")

    return "\n".join(lines)


def _catalog_section() -> str:
    return (
        "=== CATALOG ACCESS ===\n"
        "You have access to the simulation run catalog via the query_catalog tool.\n"
        "Call query_catalog whenever the user asks about past or previous simulations,\n"
        "run history, past results, or whether a particular setup has been run before.\n"
        "Examples: 'what simulations have I run?', 'show me past DMRG runs',\n"
        "'what was the ground energy for heisenberg N=10?', 'have I run TFIM before?'\n"
        "The tool accepts optional filters: algorithm, model, limit (default 10).\n"
        "Each entry returned contains: run_id, timestamp, core (algorithm, N, S),\n"
        "model (name, params), results_summary, and status.\n"
        "After receiving catalog results, summarize them clearly for the user —\n"
        "highlight run_id, timestamp, N, model, and key result values.\n"
        "Do NOT call submit_config in response to a catalog query."
    )


def _observable_tools_section() -> str:
    return (
        "=== OBSERVABLE CALCULATIONS ===\n"
        "You can compute observables on past simulation runs using the calculate_observable tool.\n"
        "Use this when the user asks to measure, compute, plot, or analyze an observable on a run.\n\n"
        "Workflow:\n"
        "1. Use query_catalog to find the run_id if the user hasn't provided one.\n"
        "2. Call calculate_observable with run_id, observable_type, params, and a summary.\n"
        "3. The config will be shown to the user to confirm before calculating.\n\n"
        "Common observable types and their required params:\n"
        "  single_site_expectation   → {site: <int>, operator: <Z/X/Y/Sp/Sm>}\n"
        "  expectation_all_sites     → {operator: <Z/X/Y>}\n"
        "  correlation_function      → {site_i: <int>, site_j: <int>, operator: <Z/X/Y>}  SAME operator both sites. MUST have 1 ≤ site_i < site_j ≤ N\n"
        "  connected_correlation     → {site_i: <int>, site_j: <int>, operator: <Z/X/Y>}  SAME operator, subtracts mean. MUST have 1 ≤ site_i < site_j ≤ N\n"
        "  two_site_expectation      → {site_i: <int>, site_j: <int>, operator_i: <Z/X/Y>, operator_j: <Z/X/Y>}  DIFFERENT operators at each site (e.g. XZ). MUST have 1 ≤ site_i < site_j ≤ N\n"
        "  correlation_matrix        → {operator: <Z/X/Y>}\n"
        "  entanglement_entropy      → {bond: <int>}\n"
        "  energy_expectation        → {}\n"
        "  energy_variance           → {}\n"
        "  boson_number              → {} (spinboson systems only)\n"
        "CRITICAL: Use correlation_function (not two_site_expectation) when the user asks for ZZ, XX, YY "
        "or any same-operator correlator. two_site_expectation is ONLY for mixed operators like XZ.\n\n"
        "Selection defaults to 'all' (every saved sweep/step). "
        "Use 'time_range' for TDVP/ed_time_evolution when user specifies a time window.\n"
        "Do NOT call calculate_observable for general questions — only when the user explicitly "
        "wants to compute a NEW observable.\n\n"
        "To PLOT EXISTING observable results (already in data_obs/):\n"
        "1. Call query_obs_catalog with filters (observable_type, sim_algorithm, sim_model_name).\n"
        "2. Pick the best matching entry from the results.\n"
        "3. Call show_observable_results with that obs_run_id — this displays the plot immediately.\n"
        "Use this path when the user says 'show', 'plot', 'display', or 'view' an observable, "
        "or asks about a previous calculation. "
        "Only use calculate_observable if no existing result matches what the user wants."
    )


def _general_questions_section(models: dict) -> str:
    all_models = [
        f"{entry.get('display_name', name)} ({entry.get('system_type', 'spin')})"
        for name, entry in models["prebuilt_models"].items()
    ]
    model_list = ", ".join(all_models)

    user_models = models.get("user_models", {}).get("models", {})
    user_note = ""
    if user_models:
        user_note = f" User-registered models also available: {', '.join(user_models)}."

    return (
        "=== GENERAL QUESTIONS ===\n"
        "If the user asks what you can do, what models are available, or any other\n"
        "general question about TNCodebase, answer conversationally and helpfully.\n"
        "Do NOT try to gather simulation parameters in response to a general question.\n"
        "Only begin collecting parameters when the user expresses a clear intent to run a simulation.\n\n"
        f"Available models: {model_list}.{user_note}\n"
        "Four algorithm types: ed_spectrum, ed_time_evolution (ED, exact, N<=14 for spin-1/2),\n"
        "dmrg (ground state, any N), tdvp (real-time dynamics, any N)."
    )
