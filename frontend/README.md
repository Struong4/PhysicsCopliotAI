# Frontend

## Config Builder

Interactive web form for generating simulation configuration files.

### What It Does

- Builds valid `config.json` files through a visual interface
- Prevents typos and ensures consistent formatting
- Supports all prebuilt models and states
- Auto-validates parameters (e.g., n_exp < N/2)

### How to Run

**Linux:**
```bash
xdg-open frontend/config_builder.html
```

**macOS:**
```bash
open frontend/config_builder.html
```

**Windows:**
```cmd
start tools\config_builder.html
```

Or simply double-click the file in your file manager.

### Workflow

1. Open `config_builder.html` in browser
2. Fill out the form (System → Model → State → Algorithm)
3. Click "Download config.json"
4. Move the file to your project directory
5. Run your simulation:
   ```bash
   julia run.jl
   ```

### Supported Configurations

**Systems:** Spin, Spin-Boson

**Models:**
- Transverse Field Ising
- Heisenberg
- Long-Range Ising
- Ising-Dicke
- Long-Range Ising-Dicke

**States:** Random, Polarized, Néel, Kink, Domain

**Algorithms:** DMRG, TDVP

### coming soon : custom model and state builders

