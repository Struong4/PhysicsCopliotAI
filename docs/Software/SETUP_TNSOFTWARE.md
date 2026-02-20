# TNSoftware Pipeline Automation - Setup Guide

## Your Project Structure

```
/home/nishan/PD_UMBC/Research/Software_Dev/TNSoftware/
├── src/                    ← Your engines (Database, Runners, etc.)
├── tools/                  ← config_builder_v4.html is here
├── data/                   ← Simulation data saves here
├── data_obs/               ← Observable data saves here
├── examples/
├── docs/
└── test/
```

## Installation (3 Steps - 5 Minutes)

### Step 1: Copy Files to Project Root

Copy these 3 files to `/home/nishan/PD_UMBC/Research/Software_Dev/TNSoftware/`:

```bash
cd /home/nishan/PD_UMBC/Research/Software_Dev/TNSoftware/

# Copy the new files
cp /path/to/downloaded/start_server.jl .
cp /path/to/downloaded/pipeline_server.jl .
cp /path/to/downloaded/pipeline_automation.js tools/
```

Your directory should now look like:

```
TNSoftware/
├── start_server.jl          ← NEW
├── pipeline_server.jl       ← NEW
├── tools/
│   ├── config_builder_v4.html
│   └── pipeline_automation.js  ← NEW
├── src/
│   ├── Database/
│   │   ├── database_utils.jl
│   │   ├── database_catalog.jl
│   │   ├── database_observables_utils.jl
│   │   └── database_observables_catalog.jl
│   └── Runners/
│       ├── run_simulation.jl
│       └── run_Observable.jl
├── data/
└── data_obs/
```

### Step 2: Install HTTP.jl (if not already installed)

```bash
julia -e 'using Pkg; Pkg.add("HTTP")'
```

### Step 3: Modify config_builder_v4.html

Open `tools/config_builder_v4.html` and add **ONE LINE** before the closing `</body>` tag:

Find the end of the file (around line 2563):

```html
        });
    </script>
</body>
</html>
```

Change to:

```html
        });
    </script>
    
    <script src="pipeline_automation.js"></script>  ← ADD THIS LINE
    
</body>
</html>
```

**That's it!** Setup complete.

---

## Starting the Server

### From Project Root

```bash
cd /home/nishan/PD_UMBC/Research/Software_Dev/TNSoftware
julia start_server.jl
```

You should see:

```
======================================================================
TNSoftware Pipeline Server
======================================================================

Project root: /home/nishan/PD_UMBC/Research/Software_Dev/TNSoftware

Configuration:
  Source code:   /home/nishan/PD_UMBC/Research/Software_Dev/TNSoftware/src
  Tools (GUI):   /home/nishan/PD_UMBC/Research/Software_Dev/TNSoftware/tools
  Data:          /home/nishan/PD_UMBC/Research/Software_Dev/TNSoftware/data
  Observables:   /home/nishan/PD_UMBC/Research/Software_Dev/TNSoftware/data_obs

Loading dependencies...

Loading TNSoftware modules from src/...
----------------------------------------------------------------------
Loading database utilities...
  ✓ Loading /home/nishan/.../src/Database/database_utils.jl
  ✓ Loading /home/nishan/.../src/Database/database_catalog.jl
  ...

All modules loaded successfully!

======================================================================
PIPELINE AUTOMATION SERVER - TNSoftware
======================================================================
Starting server on http://127.0.0.1:8080

Endpoints:
  POST   /api/run              - Run pipeline
  GET    /api/status/:id       - Check status
  GET    /api/catalog          - List all runs
  GET    /api/active           - List running pipelines
  GET    /                     - Web interface

Open http://127.0.0.1:8080 in your browser to use the GUI

Press Ctrl+C to stop server
======================================================================
```

### From Anywhere (Advanced)

The server uses absolute paths, so you can start it from anywhere:

```bash
cd /tmp/
julia /home/nishan/PD_UMBC/Research/Software_Dev/TNSoftware/start_server.jl
```

It will still:
- Load modules from `.../TNSoftware/src/`
- Save data to `.../TNSoftware/data/`
- Save observables to `.../TNSoftware/data_obs/`

---

## Using the GUI

### 1. Open Browser

Navigate to: **http://localhost:8080**

You should see your config builder with a new **green "▶ Run Pipeline"** button in the preview section.

### 2. Configure Your Simulation

Use the GUI as normal to set up:
- System (N, S, etc.)
- Model (Heisenberg, custom, etc.)
- Algorithm (DMRG, TDVP, ED)
- Initial state
- [Analysis mode] Observable type and parameters

### 3. Run Pipeline

Click **"▶ Run Pipeline"**

You'll see real-time status:

```
⏳ Queued
   Pipeline queued

⚙️ Running
   Starting simulation...

✓ Completed
   Simulation completed successfully
   Run ID: 20241104_153045_a3f5b2c1
   Directory: /home/nishan/.../data/dmrg/20241104_153045_a3f5b2c1
```

### 4. Check Results

Your data is saved to:

**Simulation mode:**
```
data/dmrg/20241104_153045_a3f5b2c1/
├── config.json
├── metadata.json
└── state_sweep_*.jld2
```

**Analysis mode:**
```
data/dmrg/20241104_153045_a3f5b2c1/          ← Simulation data
└── ...

data_obs/dmrg/sim_id/obs_id/                  ← Observable data
├── observable_config.json
├── metadata.json
└── observable_sweep_*.jld2
```

---

## Customizing start_server.jl

The `start_server.jl` file attempts to **auto-detect and load** your modules.

### If Auto-Detection Doesn't Work

Edit `start_server.jl` around line 60-120 to manually specify your files:

```julia
# Example: If your files are directly in src/
include(joinpath(SRC_DIR, "database_utils.jl"))
include(joinpath(SRC_DIR, "run_simulation.jl"))

# Or if they're in subdirectories:
include(joinpath(SRC_DIR, "Database", "database_utils.jl"))
include(joinpath(SRC_DIR, "Runners", "run_simulation.jl"))
```

### Finding Your File Structure

From your project root:

```bash
cd /home/nishan/PD_UMBC/Research/Software_Dev/TNSoftware
find src -name "*.jl" | head -20
```

This shows where your `.jl` files are located.

---

## Testing

### Test 1: Simple Simulation

1. Open http://localhost:8080
2. Select "Simulation" mode
3. Choose DMRG algorithm
4. Set N=4 (small system for fast test)
5. Choose Heisenberg model
6. Click "Run Pipeline"
7. Should complete in seconds

### Test 2: Check Data

```bash
ls data/dmrg/
# Should show: 20241104_153045_xxxxxxxx/

ls data/dmrg/20241104_153045_xxxxxxxx/
# Should show: config.json  metadata.json  state_sweep_1.jld2  ...
```

### Test 3: Deduplication

1. Run the same config again (don't change anything)
2. Should instantly return: "Simulation already completed (found existing run)"
3. No new computation - reuses existing data!

---

## Troubleshooting

### "Module not found" when starting server

**Problem:** Can't find `database_utils.jl` or other files

**Solution:** Check your actual file locations:

```bash
find src -name "database_utils.jl"
```

Then edit `start_server.jl` to match the actual path.

### Button doesn't appear in GUI

**Problem:** JavaScript not loaded

**Solution:**
1. Check `tools/pipeline_automation.js` exists
2. Check you added `<script src="pipeline_automation.js"></script>` to HTML
3. Hard refresh browser: Ctrl+Shift+R

### "Connection refused"

**Problem:** Server not running

**Solution:** Start it with `julia start_server.jl`

### Server starts but runs fail

**Problem:** Your runner functions aren't working

**Solution:**
1. Check server terminal for Julia errors
2. Test your runners work normally:
   ```julia
   using JSON
   config = JSON.parsefile("examples/some_config.json")
   result, run_id, run_dir = run_simulation_from_config(config)
   ```

---

## Advanced: Running in Background

### Using screen (Recommended)

```bash
# Start new screen session
screen -S tn_server

# Start server
cd /home/nishan/PD_UMBC/Research/Software_Dev/TNSoftware
julia start_server.jl

# Detach: Press Ctrl+A, then D
# Server keeps running in background

# Reattach later
screen -r tn_server

# Kill server
screen -X -S tn_server quit
```

### Using nohup

```bash
cd /home/nishan/PD_UMBC/Research/Software_Dev/TNSoftware
nohup julia start_server.jl > server.log 2>&1 &

# Server runs in background
# Logs go to server.log

# Stop server
pkill -f start_server.jl
```

---

## What the Files Do

**start_server.jl:**
- Detects project root (`@__DIR__`)
- Sets up paths to `src/`, `tools/`, `data/`, `data_obs/`
- Loads all your modules from `src/`
- Starts the HTTP server

**pipeline_server.jl:**
- Creates HTTP server on port 8080
- Handles API requests (`/api/run`, `/api/status`, etc.)
- Calls your existing functions:
  - `run_simulation_from_config()`
  - `run_observable_calculation_from_config()`
- Serves HTML from `tools/config_builder_v4.html`

**pipeline_automation.js:**
- Adds "Run Pipeline" button to GUI
- Sends config to server via HTTP POST
- Polls for status updates
- Shows progress in browser

**Your code doesn't change!** The server just provides a web interface.

---

## Next Steps

Once working:

1. ✅ Test simulation mode
2. ✅ Test analysis mode
3. ✅ Verify deduplication
4. 🚀 Use for real research!

Future enhancements:
- Progress bars (track sweep numbers)
- Live plotting
- Queue multiple runs
- Email notifications
- Cluster integration

---

## File Checklist

Before starting server:

- [x] `start_server.jl` in project root
- [x] `pipeline_server.jl` in project root
- [x] `pipeline_automation.js` in `tools/`
- [x] Modified `tools/config_builder_v4.html` (added script tag)
- [x] HTTP.jl installed
- [x] All your existing code in `src/`

## Server Status Check

```bash
# Check if server is running
curl http://localhost:8080/api/catalog

# Should return: []  (empty catalog if no runs yet)
# If error → server not running
```

---

## Support

If you encounter issues:

1. Check server terminal for error messages
2. Check browser console (F12) for JavaScript errors
3. Verify all files are in correct locations
4. Test your runners work independently first

**Ready to start? Run:**

```bash
cd /home/nishan/PD_UMBC/Research/Software_Dev/TNSoftware
julia start_server.jl
```

Then open: **http://localhost:8080**
