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
        _general_questions_section(models_reg),
        _result_interpretation_section(),
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
        for algo, triggers in task_routing.items():
            sample = ", ".join(f'"{t}"' for t in triggers[:4])
            lines.append(f"  {sample} -> {algo}")

    model_aliases = keywords.get("model_aliases", {})
    if model_aliases:
        lines += ["", "Model name recognition:"]
        for model, aliases in model_aliases.items():
            sample = ", ".join(f'"{a}"' for a in aliases[:3])
            lines.append(f"  {sample} -> {model}")

    return "\n".join(lines)


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
