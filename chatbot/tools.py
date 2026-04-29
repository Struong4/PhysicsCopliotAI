"""
Tool spec definitions for the Bedrock converse API.
Each dict is passed directly as a toolSpec inside toolConfig.
"""

SUBMIT_CONFIG_TOOL = {
    "name": "submit_config",
    "description": (
        "Call this ONLY when you have gathered all required information and are "
        "ready to propose a complete, valid simulation config to the user. "
        "Do not call for partial configs. "
        "Set auto_run to true ONLY when the user has clearly confirmed they want to "
        "execute immediately (e.g. 'run it', 'go ahead', 'I\\'m ready', 'yes execute it'). "
        "Leave auto_run false (default) when proposing a config for the user to review first."
    ),
    "inputSchema": {
        "json": {
            "type": "object",
            "properties": {
                "system": {
                    "type": "object",
                    "description": "System block: {type, N (or N_spins for spinboson), S, dtype, nmax}. Do NOT include N in model params — the server handles that.",
                },
                "model": {
                    "type": "object",
                    "description": "Model block: {name, params: {J, h, g, ...}}. Do NOT include N in params — the server adds it automatically for TN algorithms.",
                },
                "algorithm": {
                    "type": "object",
                    "description": (
                        "Algorithm block with flat params: {type, chi_max, n_sweeps, dt, krylov_dim, ...}. "
                        "Do NOT nest into solver/options/run sub-dicts — pass all params flat at the top level."
                    ),
                },
                "state": {
                    "type": "object",
                    "description": "State block: {type, params: {bond_dim}} for TN random; {type, name, params} for prebuilt. Omit entirely for ed_spectrum.",
                },
                "summary": {
                    "type": "string",
                    "description": "One plain-English sentence describing what this simulation does",
                },
                "auto_run": {
                    "type": "boolean",
                    "description": (
                        "If true, execute the simulation immediately without waiting for "
                        "the user to click Confirm. Only set true when the user explicitly "
                        "says to run now (e.g. 'run it', 'go ahead', 'I\\'m ready')."
                    ),
                },
            },
            "required": ["system", "model", "algorithm", "summary"],
        }
    },
}

QUERY_OBS_CATALOG_TOOL = {
    "name": "query_obs_catalog",
    "description": (
        "Search the observable calculations catalog to find already-computed observables. "
        "Use this when the user wants to plot, view, or retrieve existing observable results "
        "without running a new calculation. Returns obs_run_id entries with metadata."
    ),
    "inputSchema": {
        "json": {
            "type": "object",
            "properties": {
                "observable_type": {
                    "type": "string",
                    "description": "Filter by observable type (e.g. correlation_function, entanglement_entropy). Omit for all.",
                },
                "sim_algorithm": {
                    "type": "string",
                    "description": "Filter by simulation algorithm: dmrg, tdvp, ed_spectrum, ed_time_evolution.",
                },
                "sim_model_name": {
                    "type": "string",
                    "description": "Filter by model name (e.g. heisenberg, transverse_field_ising).",
                },
                "limit": {
                    "type": "integer",
                    "description": "Maximum results to return (default 10, max 50).",
                },
            },
        }
    },
}

SHOW_OBSERVABLE_RESULTS_TOOL = {
    "name": "show_observable_results",
    "description": (
        "Call this after querying the obs catalog to display an existing observable calculation "
        "in the right panel. Use the obs_run_id from query_obs_catalog results."
    ),
    "inputSchema": {
        "json": {
            "type": "object",
            "properties": {
                "obs_run_id": {
                    "type": "string",
                    "description": "The observable run ID to display (from query_obs_catalog results)",
                },
                "summary": {
                    "type": "string",
                    "description": "One sentence describing what is being shown",
                },
            },
            "required": ["obs_run_id", "summary"],
        }
    },
}

CALCULATE_OBSERVABLE_TOOL = {
    "name": "calculate_observable",
    "description": (
        "Call this when the user wants to compute or analyze an observable on a past simulation run. "
        "Use query_catalog first to find the run_id if not already known. "
        "Set auto_run to true ONLY when the user has clearly confirmed they want to calculate immediately "
        "(e.g. 'run it', 'go ahead', 'yes calculate it'). "
        "Leave auto_run false (default) to show the config for review first."
    ),
    "inputSchema": {
        "json": {
            "type": "object",
            "properties": {
                "run_id": {
                    "type": "string",
                    "description": "The simulation run_id from the catalog (e.g. 20260220_110253_32cff383)",
                },
                "observable_type": {
                    "type": "string",
                    "description": (
                        "Observable type key. One of: single_site_expectation, expectation_all_sites, "
                        "subsystem_expectation_sum, two_site_expectation, correlation_function, "
                        "connected_correlation, correlation_matrix, entanglement_entropy, "
                        "entanglement_spectrum, energy_expectation, energy_variance, "
                        "boson_number, boson_distribution, boson_field, boson_spin_entanglement"
                    ),
                },
                "params": {
                    "type": "object",
                    "description": (
                        "Observable parameters. Required keys by type: "
                        "single_site_expectation: {site, operator}. "
                        "expectation_all_sites: {operator}. "
                        "subsystem_expectation_sum: {operator, l, m} — l and m are 1-based start/end site indices of the subsystem (both required). "
                        "correlation_function: {site_i, site_j, operator} — SAME operator at both sites (e.g. ZZ, XX). "
                        "connected_correlation: {site_i, site_j, operator} — same as correlation_function but subtracted. "
                        "two_site_expectation: {site_i, site_j, operator_i, operator_j} — DIFFERENT operators at each site (e.g. XZ). "
                        "correlation_matrix: {operator}. "
                        "entanglement_entropy: {bond, alpha} — alpha optional, default 1 (von Neumann). "
                        "entanglement_spectrum: {bond, n_values} — n_values optional. "
                        "energy_expectation: {}. energy_variance: {}. "
                        "inner_product: {}. state_norm: {}. "
                        "fidelity: {reference} — reference is 'initial' or 'ground_state'. "
                        "survival_probability: {}. loschmidt_echo: {}. "
                        "boson_number: {}. boson_distribution: {}. boson_field: {}. "
                        "boson_spin_entanglement: {alpha} — alpha optional, default 1. "
                        "IMPORTANT: use correlation_function (not two_site_expectation) when the user asks for "
                        "spin-spin correlation, ZZ/XX/YY correlation, or any same-operator two-point function. "
                        "Only use two_site_expectation when user explicitly wants two DIFFERENT operators. "
                        "For correlation_function/connected_correlation/two_site_expectation: "
                        "site_i MUST be strictly less than site_j, both between 1 and N."
                    ),
                },
                "selection": {
                    "type": "string",
                    "description": "Which sweeps/steps to process: 'all', 'range', 'specific', 'time_range'. Default: 'all'.",
                },
                "summary": {
                    "type": "string",
                    "description": "One plain-English sentence describing what this observable calculation will compute.",
                },
                "auto_run": {
                    "type": "boolean",
                    "description": (
                        "If true, execute the observable calculation immediately without waiting "
                        "for the user to click Confirm. Only set true when the user explicitly "
                        "says to calculate now."
                    ),
                },
            },
            "required": ["run_id", "observable_type", "params", "summary"],
        }
    },
}

REGISTER_MODEL_TOOL = {
    "name": "register_model",
    "description": (
        "Call this ONLY when the user explicitly asks to register, save, or add a new custom model "
        "to the registry. Gather ALL required fields through conversation first, then call this tool. "
        "Do NOT call this during simulation setup, observable calculations, or catalog queries."
    ),
    "inputSchema": {
        "json": {
            "type": "object",
            "properties": {
                "name": {
                    "type": "string",
                    "description": "Unique identifier key for the model (lowercase, underscores, e.g. my_ising_model)",
                },
                "display_name": {
                    "type": "string",
                    "description": "Human-readable label shown in the GUI (e.g. My Ising Model)",
                },
                "system_type": {
                    "type": "string",
                    "description": "System type: 'spin' or 'spinboson'",
                },
                "backend": {
                    "type": "string",
                    "description": "Simulation backend: 'tn' (tensor networks, DMRG/TDVP) or 'ed' (exact diagonalization)",
                },
                "description": {
                    "type": "string",
                    "description": "Optional plain-English description of what this model represents",
                },
                "channels": {
                    "type": "array",
                    "description": (
                        "Required when backend='tn'. Array of channel objects defining the Hamiltonian. "
                        "Each object is one of: "
                        "{\"type\": \"FiniteRangeCoupling\", \"op1\": \"Z\", \"op2\": \"Z\", \"range\": 1, \"strength\": 1.0} "
                        "or {\"type\": \"Field\", \"op\": \"X\", \"strength\": 0.5}"
                    ),
                },
                "terms": {
                    "type": "array",
                    "description": (
                        "Required when backend='ed'. Array of term objects defining the Hamiltonian. "
                        "Same format as channels: FiniteRangeCoupling or Field objects."
                    ),
                },
            },
            "required": ["name", "display_name", "system_type", "backend"],
        }
    },
}

REGISTER_STATE_TOOL = {
    "name": "register_state",
    "description": (
        "Call this ONLY when the user explicitly asks to register, save, or add a new custom state "
        "to the registry. Gather ALL required fields through conversation first, then call this tool. "
        "Do NOT call this during simulation setup, observable calculations, or catalog queries."
    ),
    "inputSchema": {
        "json": {
            "type": "object",
            "properties": {
                "name": {
                    "type": "string",
                    "description": "Unique identifier key for the state (lowercase, underscores, e.g. my_neel_state)",
                },
                "display_name": {
                    "type": "string",
                    "description": "Human-readable label shown in the GUI (e.g. My Neel State)",
                },
                "system_type": {
                    "type": "string",
                    "description": "System type: 'spin' or 'spinboson'",
                },
                "description": {
                    "type": "string",
                    "description": "Optional plain-English description of what this state represents physically",
                },
                "site_configs": {
                    "type": "array",
                    "description": (
                        "Array of N entries (one per spin site), each a [direction, eigenstate] pair. "
                        "direction: 'X', 'Y', or 'Z'. eigenstate: integer (for spin-1/2 Z: 1=down, 2=up). "
                        "Example for 4-site Neel: [[\"Z\",2],[\"Z\",1],[\"Z\",2],[\"Z\",1]]"
                    ),
                },
                "boson_level": {
                    "type": "integer",
                    "description": "Spinboson systems only. Initial Fock occupation of the boson site (0=vacuum).",
                },
            },
            "required": ["name", "display_name", "system_type", "site_configs"],
        }
    },
}

QUERY_CATALOG_TOOL = {
    "name": "query_catalog",
    "description": (
        "Search the simulation run catalog to answer questions about past runs. "
        "Use this when the user asks about previous simulations, past results, "
        "run history, or whether a particular simulation has been done before. "
        "Returns a concise summary per entry: run_id, timestamp, algorithm, N, model_name, "
        "model_params, final_energy, and status. Call get_simulation_details for full details."
    ),
    "inputSchema": {
        "json": {
            "type": "object",
            "properties": {
                "algorithm": {
                    "type": "string",
                    "description": "Filter by algorithm type: dmrg, tdvp, ed_spectrum, or ed_time_evolution. Omit to return all algorithms.",
                },
                "model": {
                    "type": "string",
                    "description": "Filter by model name (e.g. heisenberg, transverse_field_ising). Omit to return all models.",
                },
                "limit": {
                    "type": "integer",
                    "description": "Maximum number of results to return (default 10, max 50).",
                },
            },
        }
    },
}

GET_SIMULATION_DETAILS_TOOL = {
    "name": "get_simulation_details",
    "description": (
        "Fetch the full config, metadata, and results for a specific simulation run. "
        "Use this after query_catalog when the user wants details about a specific run, "
        "or when you need the full config to set up an observable calculation."
    ),
    "inputSchema": {
        "json": {
            "type": "object",
            "properties": {
                "run_id": {
                    "type": "string",
                    "description": "The simulation run_id (e.g. 20260220_110253_32cff383)",
                },
            },
            "required": ["run_id"],
        }
    },
}

GET_OBSERVABLE_DETAILS_TOOL = {
    "name": "get_observable_details",
    "description": (
        "Fetch the config, metadata, and a data preview for a specific observable calculation. "
        "Use this after query_obs_catalog when the user wants to know what an existing "
        "observable result contains before deciding to display it."
    ),
    "inputSchema": {
        "json": {
            "type": "object",
            "properties": {
                "obs_run_id": {
                    "type": "string",
                    "description": "The observable run ID (from query_obs_catalog results)",
                },
            },
            "required": ["obs_run_id"],
        }
    },
}

GET_RUN_STATUS_TOOL = {
    "name": "get_run_status",
    "description": (
        "Check the current status of a running or recently submitted pipeline job. "
        "Use this when the user asks whether a simulation or observable calculation is done."
    ),
    "inputSchema": {
        "json": {
            "type": "object",
            "properties": {
                "tracking_id": {
                    "type": "string",
                    "description": "The tracking_id returned when the job was submitted",
                },
            },
            "required": ["tracking_id"],
        }
    },
}

GET_AVAILABLE_MODELS_TOOL = {
    "name": "get_available_models",
    "description": (
        "List all available simulation models with their Hamiltonians, system types, and "
        "example parameters. Call this when the user asks what models are available, "
        "what Hamiltonians are supported, or needs help choosing a model."
    ),
    "inputSchema": {
        "json": {
            "type": "object",
            "properties": {
                "system_type": {
                    "type": "string",
                    "description": "Filter by system type: 'spin', 'spinboson', or omit for all.",
                },
            },
        }
    },
}

GET_AVAILABLE_ALGORITHMS_TOOL = {
    "name": "get_available_algorithms",
    "description": (
        "List all available simulation algorithms with descriptions, suitable use cases, "
        "and key parameters. Call this when the user asks what algorithms are available "
        "or needs guidance on which algorithm fits their problem."
    ),
    "inputSchema": {
        "json": {
            "type": "object",
            "properties": {},
        }
    },
}

TOOL_CONFIG = {"tools": [
    {"toolSpec": SUBMIT_CONFIG_TOOL},
    {"toolSpec": QUERY_CATALOG_TOOL},
    {"toolSpec": CALCULATE_OBSERVABLE_TOOL},
    {"toolSpec": QUERY_OBS_CATALOG_TOOL},
    {"toolSpec": SHOW_OBSERVABLE_RESULTS_TOOL},
    {"toolSpec": REGISTER_MODEL_TOOL},
    {"toolSpec": REGISTER_STATE_TOOL},
    {"toolSpec": GET_SIMULATION_DETAILS_TOOL},
    {"toolSpec": GET_OBSERVABLE_DETAILS_TOOL},
    {"toolSpec": GET_RUN_STATUS_TOOL},
    {"toolSpec": GET_AVAILABLE_MODELS_TOOL},
    {"toolSpec": GET_AVAILABLE_ALGORITHMS_TOOL},
]}
