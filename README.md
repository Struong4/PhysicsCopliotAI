# TNCodebase: AI Chatbot for Quantum Many-Body Simulations

*A natural-language interface for running quantum simulations — no Julia or JSON knowledge required*

TNCodebase is a quantum many-body simulation framework (DMRG, TDVP, Exact Diagonalization) with an AI chatbot front-end. You describe the physics you want to explore in plain English and the chatbot handles building and running the simulation for you.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

---

## How It Works

```
Browser (port 8000)
  ↕ HTTP
FastAPI chatbot server  (chatbot/app.py)
  ↕ AWS Bedrock API
Claude 3 Haiku  ←  generates simulation configs from natural language
  ↕ HTTP
Julia pipeline server  (port 8080)
  ↕ in-process
TNCodebase.run_simulation_from_config(...)
```

You chat with Claude 3 Haiku, which builds a JSON simulation config from your description and sends it to the Julia backend to execute. Once a simulation completes, you can ask the chatbot to compute and plot observables on the saved results — also through conversation.

---

## Supported Algorithms

| Algorithm | Method | Best For | System Size |
|-----------|--------|----------|-------------|
| `dmrg` | Tensor Network | Ground state search | N ~ 100–1000 |
| `tdvp` | Tensor Network | Real / imaginary time evolution | N ~ 100–1000 |
| `ed_spectrum` | Exact Diagonalization | Full spectrum, all eigenstates | N ≤ 12–14 |
| `ed_time_evolution` | Exact Diagonalization | Exact dynamics, benchmarking | N ≤ 12–14 |

**Models:** `transverse_field_ising`, `heisenberg`, `long_range_ising`, `spinboson`

---

## Supported Observables

After a simulation runs, ask the chatbot to calculate any of these on the saved state:

**Local**
- `single_site_expectation` — ⟨Oᵢ⟩ at one site (operators: X, Y, Z, S+, S-)
- `expectation_all_sites` — ⟨Oᵢ⟩ at every site (ED only)
- `subsystem_expectation_sum` — Σᵢ ⟨Oᵢ⟩ over a range of sites

**Two-point**
- `correlation_function` — ⟨Oᵢ Oⱼ⟩ (same operator at both sites)
- `connected_correlation` — ⟨Oᵢ Oⱼ⟩ − ⟨Oᵢ⟩⟨Oⱼ⟩
- `two_site_expectation` — ⟨Oᵢ Pⱼ⟩ (different operators)
- `correlation_matrix` — full N×N correlation matrix (ED only)

**Entanglement**
- `entanglement_entropy` — von Neumann or Renyi entropy at a bond
- `entanglement_spectrum` — Schmidt values at a bond

**Energy**
- `energy_expectation` — ⟨H⟩
- `energy_variance` — ⟨H²⟩ − ⟨H⟩²

**Dynamics (ED only)**
- `survival_probability` — |⟨ψ(0)|ψ(t)⟩|²
- `loschmidt_echo` — −log|⟨ψ(0)|ψ(t)⟩|²/N
- `fidelity` — overlap with initial or ground state

**Spin-boson only**
- `boson_number` — ⟨b†b⟩
- `boson_distribution` — Fock state probability distribution P(n)
- `boson_field` — ⟨a + a†⟩
- `boson_spin_entanglement` — entanglement between cavity and spin chain

---

## Quick Start (Docker)

The easiest way to run everything is with Docker Compose — it builds and starts both the Julia simulation server and the Python chatbot server in one command.

### 1. Prerequisites

- [Docker Desktop](https://www.docker.com/products/docker-desktop/) installed and running
- AWS credentials with Amazon Bedrock access (see below)

### 2. Enable Claude 3 Haiku in AWS Bedrock

1. Sign in to the [AWS Console](https://console.aws.amazon.com)
2. Navigate to **Amazon Bedrock → Model access → Manage model access**
3. Enable **Anthropic → Claude 3 Haiku**
4. Your IAM user needs the `bedrock:InvokeModel` permission in `us-east-1`

### 3. Configure Your AWS Credentials

Copy the example env file and fill in your credentials:

```bash
cp .env.example .env
```

Open `.env` and replace the placeholder values:

```
AWS_ACCESS_KEY_ID=your_access_key_id_here
AWS_SECRET_ACCESS_KEY=your_secret_access_key_here
AWS_DEFAULT_REGION=us-east-1
```

> `.env` is gitignored and will never be committed.

### 4. Start the Stack

```bash
docker compose up --build
```

This builds both containers and starts:
- Julia pipeline server at `http://localhost:8080`
- Chatbot UI at `http://localhost:8000`

Open **http://localhost:8000** in your browser and start chatting.

### Stopping

```bash
docker compose down
```

### Rebuilding after code changes

```bash
docker compose up --build
```

---

## What to Ask the Chatbot

**Running simulations:**
- *"Find the ground state of the Heisenberg model with N=50 using DMRG, chi_max=128"*
- *"Run TDVP time evolution on the transverse field Ising model, N=30, h=1.5, for total time T=5"*
- *"Run an ED spectrum of the Heisenberg model with 10 sites"*
- *"Simulate exact time evolution of the long-range Ising model, N=8, for 100 steps"*

**Computing observables on past runs:**
- *"Show the ZZ correlation function between sites 1 and 25 for my last DMRG run"*
- *"Plot the entanglement entropy at every bond for the Heisenberg ground state"*
- *"Calculate the magnetization profile ⟨Zᵢ⟩ at all sites"*
- *"What's the energy variance for run from yesterday?"*

The chatbot will ask for any missing parameters before running, and will show you the config for review before submitting.

---

## Data

Simulation results are saved to `./data/` and observable results to `./data_obs/` on your host machine (mounted as volumes in the containers), so your results persist across container restarts.

---

## Troubleshooting

**Chatbot can't reach the Julia server**
The chatbot container connects to the Julia server at `http://julia-server:8080` (Docker internal networking). Make sure both containers started successfully: `docker compose ps`.

**AWS credentials error**
Double-check your `.env` file has the correct `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY`, and that the Claude 3 Haiku model is enabled in Bedrock for `us-east-1`.

**Julia server slow to start**
The Julia container precompiles TNCodebase on first startup — this can take a few minutes. Wait for the log line `Listening on http://0.0.0.0:8080` before sending requests.

---

## License

MIT
