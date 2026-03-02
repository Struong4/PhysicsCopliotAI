// ============================================================================
// PIPELINE AUTOMATION - CLIENT-SIDE JAVASCRIPT
// ============================================================================
//
// Add this script to your config_builder.html to enable single-click
// pipeline execution.
//
// USAGE:
//   Add to HTML: <script src="pipeline_automation.js"></script>
//
// Or inline at the end of config_builder.html
//
// ============================================================================

// Server configuration
const API_BASE_URL = 'http://localhost:8080';

// Track current run
let currentTrackingId = null;
let statusCheckInterval = null;

// ============================================================================
// REGISTRY STATE
// ============================================================================

// Loaded once on init, available globally for the GUI
window.TNRegistry = {
    models:     null,
    systems:    null,
    states:     null,
    algorithms: null
};

/**
 * Fetch all four registry files from the server and store globally.
 * Called once on page load. Silently skips if server is offline.
 */
async function fetchRegistries() {
    const names = ['models', 'systems', 'states', 'algorithms'];
    for (const name of names) {
        try {
            const response = await fetch(`${API_BASE_URL}/api/registry/${name}`);
            if (response.ok) {
                window.TNRegistry[name] = await response.json();
                console.log(`[Registry] Loaded ${name}`);
            } else {
                console.warn(`[Registry] Failed to load ${name}: ${response.status}`);
            }
        } catch (e) {
            console.warn(`[Registry] Could not fetch ${name}:`, e.message);
        }
    }

    // Populate user models into the dropdown if any are registered
    if (window.TNRegistry.models) {
        const userModels = window.TNRegistry.models.user_models?.models || {};
        console.log(`[Registry] user_models found: ${Object.keys(userModels).length} model(s)`, Object.keys(userModels));
        populateUserModels(userModels);
        if (typeof renderSavedModelsList === 'function') renderSavedModelsList();
        if (typeof filterUserModelsInDropdown === 'function') filterUserModelsInDropdown();
    } else {
        console.warn('[Registry] models registry not loaded — user models will not appear');
    }

    // Populate saved states into the saved-state selector
    if (window.TNRegistry.states) {
        const userStates = window.TNRegistry.states.user_states?.states || {};
        console.log(`[Registry] user_states found: ${Object.keys(userStates).length} state(s)`, Object.keys(userStates));
        populateUserStates(userStates);
        if (typeof renderSavedStatesList === 'function') renderSavedStatesList();
    } else {
        console.warn('[Registry] states registry not loaded — user states will not appear');
    }
}

/**
 * Populate the "Saved Models" optgroup in the model dropdown from registry.
 * Creates the optgroup if it doesn't already exist.
 */
function populateUserModels(userModels) {
    const modelSelect = document.getElementById('model-name');
    if (!modelSelect) return;

    // Remove existing user optgroup if present (refresh case)
    const existing = document.getElementById('optgroup-user');
    if (existing) existing.remove();

    const entries = Object.entries(userModels);
    if (entries.length === 0) return;

    const optgroup = document.createElement('optgroup');
    optgroup.id = 'optgroup-user';
    optgroup.label = 'Saved Models';

    for (const [key, model] of entries) {
        const option = document.createElement('option');
        option.value = key;
        const backendLabel = model.backend === 'tn' ? ' [TN]' : ' [ED]';
        option.textContent = (model.display_name || key) + backendLabel;
        option.dataset.systemType = model.system_type;
        option.dataset.backend = model.backend || 'ed';
        option.dataset.userModel = 'true';
        optgroup.appendChild(option);
    }

    modelSelect.appendChild(optgroup);
    console.log(`[Registry] Populated ${entries.length} user model(s) in dropdown`);
}

/**
 * Populate the saved-states select from registry.
 * Targets the 'state-saved-name' select inside the saved state section.
 * Also wires an onchange to show a compact preview of the saved state config.
 */
function populateUserStates(userStates) {
    const select = document.getElementById('state-saved-name');
    if (!select) return;

    // Clear and reset
    select.innerHTML = '';

    const entries = Object.entries(userStates);
    if (entries.length === 0) {
        const opt = document.createElement('option');
        opt.value = '';
        opt.textContent = '— no saved states yet —';
        select.appendChild(opt);
        return;
    }

    // Blank first option
    const blank = document.createElement('option');
    blank.value = '';
    blank.textContent = '— select a saved state —';
    select.appendChild(blank);

    for (const [key, state] of entries) {
        const option = document.createElement('option');
        option.value = key;
        const systemLabel = state.system_type === 'spinboson' ? ' [spinboson]' : ' [spin]';
        option.textContent = (state.display_name || key) + systemLabel;
        select.appendChild(option);
    }

    // Wire preview on selection change
    select.onchange = function() {
        const key   = this.value;
        const entry = userStates[key];
        const prev  = document.getElementById('saved-state-preview');
        if (!prev) return;

        if (!entry) {
            prev.style.display = 'none';
            if (typeof updatePreview === 'function') updatePreview();
            return;
        }

        const N = entry.site_configs?.length ?? '?';
        let info = `${entry.display_name || key}  ·  ${entry.system_type}  ·  ${N} sites`;
        if (entry.boson_level !== undefined) info += `  ·  boson |${entry.boson_level}⟩`;
        if (entry.registered_at) info += `\nSaved: ${entry.registered_at.slice(0,16)}`;

        prev.textContent = info;
        prev.style.display = 'block';

        if (typeof updatePreview === 'function') updatePreview();
    };

    console.log(`[Registry] Populated ${entries.length} saved state(s) in dropdown`);
}

// ============================================================================
// USER MODEL / STATE REGISTRATION
// ============================================================================

/**
 * Register a named user model with the server.
 * @param {object} payload - Full entry: { name, display_name, description,
 *                           system_type, backend, channels (TN) or terms (ED) }
 */
async function registerModel(payload) {
    const { name, display_name } = payload;
    if (!name || !display_name) {
        showRegFeedback('model', 'error', 'Name and display name are required.');
        return false;
    }

    const key = name.trim().toLowerCase().replace(/\s+/g, '_').replace(/[^a-z0-9_]/g, '');
    if (!key) {
        showRegFeedback('model', 'error', 'Name must contain at least one alphanumeric character.');
        return false;
    }

    try {
        const response = await fetch(`${API_BASE_URL}/api/registry/models`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ ...payload, name: key })
        });

        const result = await response.json();
        if (!response.ok) {
            showRegFeedback('model', 'error', result.error || 'Registration failed.');
            return false;
        }

        console.log(`[Registry] Registered model: ${key} (${payload.backend})`);

        const r = await fetch(`${API_BASE_URL}/api/registry/models`);
        if (r.ok) {
            window.TNRegistry.models = await r.json();
            const userModels = window.TNRegistry.models.user_models?.models || {};
            populateUserModels(userModels);
            if (typeof renderSavedModelsList === 'function') renderSavedModelsList();
            if (typeof filterUserModelsInDropdown === 'function') filterUserModelsInDropdown();
        }

        showRegFeedback('model', 'success', result.message || `Model '${display_name}' saved.`);
        return true;

    } catch (e) {
        showRegFeedback('model', 'error', `Network error: ${e.message}`);
        return false;
    }
}

/**
 * Delete a named user model from the server registry.
 * Refreshes dropdown and registry list on success.
 */
async function deleteModel(name) {
    if (!confirm(`Delete model '${name}'? This cannot be undone.`)) return;
    try {
        const response = await fetch(`${API_BASE_URL}/api/registry/models/${encodeURIComponent(name)}`, {
            method: 'DELETE'
        });
        const result = await response.json();
        if (!response.ok) { alert(result.error || 'Delete failed.'); return; }

        console.log(`[Registry] Deleted model: ${name}`);

        const r = await fetch(`${API_BASE_URL}/api/registry/models`);
        if (r.ok) {
            window.TNRegistry.models = await r.json();
            const userModels = window.TNRegistry.models.user_models?.models || {};
            populateUserModels(userModels);
            if (typeof renderSavedModelsList === 'function') renderSavedModelsList();
            if (typeof filterUserModelsInDropdown === 'function') filterUserModelsInDropdown();
        }
    } catch (e) {
        alert(`Error: ${e.message}`);
    }
}

/**
 * Delete a named user state from the server registry.
 */
async function deleteState(name) {
    if (!confirm(`Delete state '${name}'? This cannot be undone.`)) return;
    try {
        const response = await fetch(`${API_BASE_URL}/api/registry/states/${encodeURIComponent(name)}`, {
            method: 'DELETE'
        });
        const result = await response.json();
        if (!response.ok) { alert(result.error || 'Delete failed.'); return; }

        console.log(`[Registry] Deleted state: ${name}`);

        const r = await fetch(`${API_BASE_URL}/api/registry/states`);
        if (r.ok) {
            window.TNRegistry.states = await r.json();
            const userStates = window.TNRegistry.states.user_states?.states || {};
            populateUserStates(userStates);
            if (typeof renderSavedStatesList === 'function') renderSavedStatesList();
        }
    } catch (e) {
        alert(`Error: ${e.message}`);
    }
}

/**
 * Show feedback inside the registry panel.
 * type: 'model' | 'state'
 * level: 'error' | 'success'
 */
function showRegFeedback(type, level, message) {
    const el = document.getElementById(`reg-${type}-feedback`);
    if (!el) { console[level === 'error' ? 'error' : 'log'](`[Registry] ${message}`); return; }
    const styles = level === 'error'
        ? 'padding:8px 12px; border-radius:4px; background:#f8d7da; color:#721c24; font-size:13px;'
        : 'padding:8px 12px; border-radius:4px; background:#d4edda; color:#155724; font-size:13px;';
    el.style.cssText = styles;
    el.textContent = (level === 'error' ? '✗ ' : '✓ ') + message;
    el.style.display = 'block';
    setTimeout(() => { el.style.display = 'none'; }, level === 'error' ? 6000 : 4000);
}

/**
 * Register a named user state with the server.
 * On success: refreshes registry and repopulates the state dropdown.
 *
 * @param {string} name         - Key name
 * @param {string} displayName  - Human-readable label
 * @param {string} description  - Optional description
 * @param {string} systemType   - 'spin' or 'spinboson'
 * @param {Array}  siteConfigs  - Array of [direction, eigenstate] pairs
 * @param {number|null} bosonLevel - Fock level for spinboson; null for spin
 */
async function registerState(name, displayName, description, systemType, siteConfigs, bosonLevel = null) {
    if (!name || !displayName || !systemType || !siteConfigs) {
        showRegFeedback('state', 'error', 'Name, display name, system type, and site configs are required.');
        return false;
    }

    const key = name.trim().toLowerCase().replace(/\s+/g, '_').replace(/[^a-z0-9_]/g, '');
    if (!key) {
        showRegFeedback('state', 'error', 'Name must contain at least one alphanumeric character.');
        return false;
    }

    const payload = { name: key, display_name: displayName, description, system_type: systemType, site_configs: siteConfigs };
    if (bosonLevel !== null) payload.boson_level = bosonLevel;

    try {
        const response = await fetch(`${API_BASE_URL}/api/registry/states`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(payload)
        });

        const result = await response.json();
        if (!response.ok) {
            showRegFeedback('state', 'error', result.error || 'Registration failed.');
            return false;
        }

        console.log(`[Registry] Registered state: ${key}`);

        const r = await fetch(`${API_BASE_URL}/api/registry/states`);
        if (r.ok) {
            window.TNRegistry.states = await r.json();
            const userStates = window.TNRegistry.states.user_states?.states || {};
            populateUserStates(userStates);
            if (typeof renderSavedStatesList === 'function') renderSavedStatesList();
        }

        showRegFeedback('state', 'success', result.message || `State '${displayName}' saved.`);
        return true;

    } catch (e) {
        showRegFeedback('state', 'error', `Network error: ${e.message}`);
        return false;
    }
}

// ============================================================================
// UI ELEMENTS
// ============================================================================

/**
 * Add "Run Pipeline" button to the GUI
 */
function addRunPipelineButton() {
    // Find the button group in the preview section
    const previewContainer = document.querySelector('.preview-container');
    if (!previewContainer) return;
    
    // Find or create button group
    let buttonGroup = previewContainer.querySelector('.btn-group');
    if (!buttonGroup) {
        // Create button group after preview header
        buttonGroup = document.createElement('div');
        buttonGroup.className = 'btn-group';
        previewContainer.insertBefore(buttonGroup, previewContainer.querySelector('#json-preview'));
    }
    
    // Create Run button
    const runButton = document.createElement('button');
    runButton.id = 'run-pipeline-btn';
    runButton.className = 'btn btn-success';
    runButton.innerHTML = '▶ Run Pipeline';
    runButton.style.background = '#28a745';
    runButton.onclick = runPipeline;
    
    // Add to button group (prepend so it's first)
    buttonGroup.insertBefore(runButton, buttonGroup.firstChild);
    
    // Create status display
    const statusDiv = document.createElement('div');
    statusDiv.id = 'pipeline-status';
    statusDiv.style.cssText = `
        margin-top: 15px;
        padding: 15px;
        border-radius: 6px;
        background: #f8f9fa;
        display: none;
    `;
    previewContainer.appendChild(statusDiv);
}

/**
 * Update UI to show pipeline status
 */
function updateStatus(status, message, details = null) {
    const statusDiv = document.getElementById('pipeline-status');
    const runButton = document.getElementById('run-pipeline-btn');
    
    if (!statusDiv) return;
    
    statusDiv.style.display = 'block';
    
    // Status icons and colors
    const statusConfig = {
        queued: { icon: '⏳', color: '#ffc107', label: 'Queued' },
        running: { icon: '⚙️', color: '#17a2b8', label: 'Running' },
        completed: { icon: '✓', color: '#28a745', label: 'Completed' },
        failed: { icon: '✗', color: '#dc3545', label: 'Failed' }
    };
    
    const config = statusConfig[status] || statusConfig.queued;
    
    let html = `
        <div style="display: flex; align-items: center; gap: 10px; margin-bottom: 10px;">
            <span style="font-size: 24px;">${config.icon}</span>
            <div>
                <strong style="color: ${config.color};">${config.label}</strong>
                <div style="font-size: 14px; color: #666;">${message}</div>
            </div>
        </div>
    `;
    
    if (details) {
        html += '<div style="margin-top: 10px; padding: 10px; background: white; border-radius: 4px; font-family: monospace; font-size: 12px;">';
        if (details.run_id) html += `<div><strong>Run ID:</strong> ${details.run_id}</div>`;
        if (details.run_dir) html += `<div><strong>Directory:</strong> ${details.run_dir}</div>`;
        if (details.obs_run_id) html += `<div><strong>Observable Run ID:</strong> ${details.obs_run_id}</div>`;
        if (details.obs_run_dir) html += `<div><strong>Observable Directory:</strong> ${details.obs_run_dir}</div>`;
        if (details.deduplicated) html += `<div style="color: #ffc107;"><strong>Note:</strong> Used existing result (deduplication)</div>`;
        html += '</div>';
    }
    
    statusDiv.innerHTML = html;
    
    // Update button state
    if (status === 'running' || status === 'queued') {
        runButton.disabled = true;
        runButton.innerHTML = '⚙️ Running...';
    } else {
        runButton.disabled = false;
        runButton.innerHTML = '▶ Run Pipeline';
    }
}

// ============================================================================
// API COMMUNICATION
// ============================================================================

/**
 * Run the pipeline with current config
 */
async function runPipeline() {
    try {
        // Get current config and mode from the GUI
        const config = buildConfig();  // This function exists in config_builder.html
        const mode = currentMode;      // This variable exists in config_builder.html
        
        updateStatus('queued', 'Sending request to server...');
        
        // Send to server
        const response = await fetch(`${API_BASE_URL}/api/run`, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json'
            },
            body: JSON.stringify({
                mode: mode,
                config: config
            })
        });
        
        if (!response.ok) {
            throw new Error(`Server error: ${response.statusText}`);
        }
        
        const result = await response.json();
        currentTrackingId = result.tracking_id;
        
        updateStatus('queued', result.message);
        
        // Start polling for status
        startStatusPolling();
        
    } catch (error) {
        console.error('Pipeline error:', error);
        updateStatus('failed', `Error: ${error.message}`);
    }
}

/**
 * Poll server for status updates
 */
function startStatusPolling() {
    if (statusCheckInterval) {
        clearInterval(statusCheckInterval);
    }
    
    statusCheckInterval = setInterval(async () => {
        try {
            const response = await fetch(`${API_BASE_URL}/api/status/${currentTrackingId}`);
            
            if (!response.ok) {
                console.error('Status check failed:', response.statusText);
                return;
            }
            
            const status = await response.json();
            
            // Update UI
            updateStatus(
                status.status,
                status.last_message,
                status.result
            );
            
            // Stop polling if completed or failed
            if (status.status === 'completed' || status.status === 'failed') {
                clearInterval(statusCheckInterval);
                statusCheckInterval = null;
            }
            
        } catch (error) {
            console.error('Status polling error:', error);
        }
    }, 1000);  // Poll every second
}

/**
 * Check if server is available
 */
async function checkServerStatus() {
    try {
        const response = await fetch(`${API_BASE_URL}/api/catalog`, {
            method: 'GET'
        });
        return response.ok;
    } catch (error) {
        return false;
    }
}

// ============================================================================
// INITIALIZATION
// ============================================================================

/**
 * Initialize pipeline automation when page loads
 */
async function initializePipelineAutomation() {
    console.log('Initializing pipeline automation...');
    
    // Add UI elements
    addRunPipelineButton();
    
    // Check server connection
    const serverOnline = await checkServerStatus();
    if (!serverOnline) {
        console.warn('Pipeline server not detected. Run: julia start_server.jl');
        const statusDiv = document.getElementById('pipeline-status');
        if (statusDiv) {
            statusDiv.style.display = 'block';
            statusDiv.innerHTML = `
                <div style="color: #856404; background: #fff3cd; padding: 10px; border-radius: 4px;">
                    ⚠️ <strong>Server offline.</strong> Start the server with: <code>julia start_server.jl</code>
                </div>
            `;
        }
    } else {
        console.log('Pipeline server connected!');
        // Load registries and populate user models/states in the GUI
        await fetchRegistries();
    }
}

// Wait for DOM to load, then initialize
if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', initializePipelineAutomation);
} else {
    initializePipelineAutomation();
}

// ============================================================================
// EXPORT FOR INLINE USE
// ============================================================================

window.runPipeline = runPipeline;
window.checkServerStatus = checkServerStatus;
window.fetchRegistries = fetchRegistries;
window.registerModel = registerModel;
window.registerState = registerState;
window.deleteModel = deleteModel;
window.deleteState = deleteState;
window.populateUserModels = populateUserModels;
window.populateUserStates = populateUserStates;
window.showRegFeedback = showRegFeedback;
