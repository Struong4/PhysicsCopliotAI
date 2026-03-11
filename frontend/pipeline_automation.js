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
        // Get current config from the GUI
        const config = buildConfig();  // This function exists in config_builder.html

        updateStatus('queued', 'Sending request to server...');

        // Send to server
        const response = await fetch(`${API_BASE_URL}/api/run`, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json'
            },
            body: JSON.stringify({
                mode: 'simulation',
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
        // Load observables registry
        await fetchObservablesRegistry();
        // Load catalog metadata for dynamic query filters
        await fetchCatalogInfo().catch(e => console.warn('Catalog info not available:', e.message));
        await fetchObservableCatalogInfo().catch(e => console.warn('Observable catalog info not available:', e.message));
    }
}

// Wait for DOM to load, then initialize
if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', initializePipelineAutomation);
} else {
    initializePipelineAutomation();
}

// ============================================================================
// QUERY & CALCULATE API
// ============================================================================

/**
 * Query simulation catalog via REST API.
 * @param {object} filters - Key-value pairs for query parameters
 * @returns {Promise<{count: number, results: Array}>}
 */
async function querySimulations(filters = {}) {
    const params = new URLSearchParams(filters);
    const response = await fetch(`${API_BASE_URL}/api/query/simulations?${params}`);
    if (!response.ok) throw new Error(`Query failed: ${response.statusText}`);
    return response.json();
}

/**
 * Query observable catalog via REST API.
 * @param {object} filters - Key-value pairs for query parameters
 * @returns {Promise<{count: number, results: Array}>}
 */
async function queryObservables(filters = {}) {
    const params = new URLSearchParams(filters);
    const response = await fetch(`${API_BASE_URL}/api/query/observables?${params}`);
    if (!response.ok) throw new Error(`Query failed: ${response.statusText}`);
    return response.json();
}

/**
 * Get simulation results and metadata for a specific run.
 * @param {string} runId - Simulation run ID
 * @returns {Promise<object>}
 */
async function getSimulationResults(runId) {
    const response = await fetch(`${API_BASE_URL}/api/results/simulations/${encodeURIComponent(runId)}`);
    if (!response.ok) throw new Error(`Results fetch failed: ${response.statusText}`);
    return response.json();
}

/**
 * Get observable results for a specific observable run.
 * @param {string} obsRunId - Observable run ID
 * @returns {Promise<object>}
 */
async function getObservableResults(obsRunId) {
    const response = await fetch(`${API_BASE_URL}/api/results/observables/${encodeURIComponent(obsRunId)}`);
    if (!response.ok) throw new Error(`Results fetch failed: ${response.statusText}`);
    return response.json();
}

/**
 * Calculate observable on existing simulation data (run_id based).
 * @param {string} runId - Simulation run ID
 * @param {object} observable - {type, params}
 * @param {object} selection - {type: "all"} or {type: "range", range: [1, 10]}
 * @returns {Promise<{status, tracking_id, message}>}
 */
async function calculateObservable(runId, observable, selection = { type: 'all' }) {
    const response = await fetch(`${API_BASE_URL}/api/observables/calculate`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
            run_id: runId,
            observable: observable,
            selection: selection
        })
    });
    if (!response.ok) {
        const err = await response.json().catch(() => ({}));
        throw new Error(err.error || `Calculate failed: ${response.statusText}`);
    }
    return response.json();
}

/**
 * Fetch the observables registry for dynamic observable selection.
 * @returns {Promise<object|null>}
 */
async function fetchObservablesRegistry() {
    try {
        const response = await fetch(`${API_BASE_URL}/api/registry/observables`);
        if (response.ok) {
            const data = await response.json();
            window.TNRegistry.observables = data;
            console.log('[Registry] Loaded observables');
            populateObservableSelector('qc-observable-type');
            return data;
        }
    } catch (e) {
        console.warn('[Registry] Could not fetch observables:', e.message);
    }
    return null;
}

// ============================================================================
// QUERY & CALCULATE UI
// ============================================================================

/** Currently selected simulation run_id from query results */
let selectedSimRunId = null;
let obsCalcTrackingId = null;
let obsCalcPollInterval = null;

/**
 * Populate the observable type dropdown from registry data.
 * Falls back to hardcoded options if registry unavailable.
 */
function populateObservableSelector(targetSelectId = 'qc-observable-type') {
    const select = document.getElementById(targetSelectId);
    if (!select) return;

    const registry = window.TNRegistry?.observables;
    if (!registry || !registry.observables) return;

    select.innerHTML = '';

    // Group by category
    const categories = registry.categories || {};
    const obsByCategory = {};

    for (const [key, obs] of Object.entries(registry.observables)) {
        const cat = obs.category || 'other';
        if (!obsByCategory[cat]) obsByCategory[cat] = [];
        obsByCategory[cat].push({ key, ...obs });
    }

    for (const [catKey, catInfo] of Object.entries(categories)) {
        const items = obsByCategory[catKey];
        if (!items || items.length === 0) continue;

        const optgroup = document.createElement('optgroup');
        optgroup.label = catInfo.display_name || catKey;

        for (const obs of items) {
            const option = document.createElement('option');
            option.value = obs.key;
            option.textContent = obs.display_name || obs.key;
            if (obs.description) option.title = obs.description;
            option.dataset.description = obs.description || '';
            option.dataset.params = JSON.stringify(obs.params || {});
            option.dataset.backends = JSON.stringify(obs.backends || {});
            optgroup.appendChild(option);
        }

        select.appendChild(optgroup);
    }

    // Trigger param rendering for initial selection
    if (select.onchange) select.onchange();
}

/**
 * Render dynamic parameter inputs for the selected observable.
 */
function renderObservableParams(selectId = 'qc-observable-type', containerId = 'qc-obs-params') {
    const select = document.getElementById(selectId);
    const container = document.getElementById(containerId);
    if (!select || !container) return;

    container.innerHTML = '';

    const registry = window.TNRegistry?.observables;
    if (!registry) return;

    const obsKey = select.value;
    const obs = registry.observables?.[obsKey];
    if (!obs) return;

    // Show observable description
    if (obs.description) {
        const descBox = document.createElement('div');
        descBox.style.cssText = 'padding:8px 10px; background:#eef6ff; border-left:3px solid #2196F3; border-radius:3px; margin-bottom:10px; font-size:12px; color:#333; line-height:1.5;';
        descBox.textContent = obs.description;

        // Show backend compatibility
        if (obs.backends) {
            const supported = Object.entries(obs.backends)
                .filter(([, v]) => v)
                .map(([k]) => k.replace('_', ' ').toUpperCase());
            if (supported.length > 0) {
                const tagRow = document.createElement('div');
                tagRow.style.cssText = 'margin-top:6px; display:flex; gap:4px; flex-wrap:wrap;';
                for (const tag of supported) {
                    const span = document.createElement('span');
                    span.style.cssText = 'font-size:10px; padding:2px 6px; background:#d4edda; color:#155724; border-radius:8px; font-weight:600;';
                    span.textContent = tag;
                    tagRow.appendChild(span);
                }
                descBox.appendChild(tagRow);
            }
        }

        container.appendChild(descBox);
    }

    if (!obs.params) return;

    for (const [paramName, paramDef] of Object.entries(obs.params)) {
        const group = document.createElement('div');
        group.className = 'form-group';
        group.style.marginBottom = '8px';

        const label = document.createElement('label');
        label.textContent = paramDef.display_name || paramName;
        label.style.fontSize = '13px';
        if (paramDef.description) label.title = paramDef.description;
        group.appendChild(label);

        // Show parameter description as hint text
        if (paramDef.description) {
            const hint = document.createElement('div');
            hint.style.cssText = 'font-size:11px; color:#888; margin:-2px 0 4px 0;';
            hint.textContent = paramDef.description;
            group.appendChild(hint);
        }

        if (paramDef.type === 'select' || paramDef.options || paramDef.allowed_values) {
            const sel = document.createElement('select');
            sel.id = `qc-obs-param-${paramName}`;
            const options = paramDef.options || paramDef.allowed_values || [];
            for (const opt of options) {
                const o = document.createElement('option');
                o.value = opt;
                o.textContent = opt;
                if (opt === paramDef.default) o.selected = true;
                sel.appendChild(o);
            }
            group.appendChild(sel);
        } else {
            const input = document.createElement('input');
            input.id = `qc-obs-param-${paramName}`;
            input.type = paramDef.type === 'float' ? 'number' : (paramDef.type === 'int' ? 'number' : 'text');
            if (paramDef.type === 'int') input.step = '1';
            if (paramDef.type === 'float') input.step = 'any';
            if (paramDef.default !== undefined) input.value = paramDef.default;
            if (paramDef.min !== undefined) input.min = paramDef.min;
            if (paramDef.minimum !== undefined) input.min = paramDef.minimum;
            group.appendChild(input);
        }

        container.appendChild(group);
    }
}

/**
 * Collect observable config from the dynamic query-calculate form.
 */
function buildQCObservableConfig() {
    const select = document.getElementById('qc-observable-type');
    if (!select) return null;

    const obsKey = select.value;
    if (!obsKey) return null;  // placeholder selected, no observable chosen
    const registry = window.TNRegistry?.observables;
    const obsDef = registry?.observables?.[obsKey];

    const params = {};
    if (obsDef?.params) {
        for (const [paramName, paramDef] of Object.entries(obsDef.params)) {
            const el = document.getElementById(`qc-obs-param-${paramName}`);
            if (!el) continue;
            let val = el.value;
            if (paramDef.type === 'int') val = parseInt(val);
            else if (paramDef.type === 'float') val = parseFloat(val);
            if (val !== '' && val !== undefined && !Number.isNaN(val)) {
                params[paramName] = val;
            }
        }
    }

    return { type: obsKey, params };
}

/**
 * Build selection config from the query-calculate form.
 */
function buildQCSelectionConfig() {
    const selType = document.getElementById('qc-selection-type')?.value || 'all';
    const config = { selection: selType };

    if (selType === 'range') {
        config.range = [
            parseInt(document.getElementById('qc-sel-range-start')?.value || '1'),
            parseInt(document.getElementById('qc-sel-range-end')?.value || '20')
        ];
    } else if (selType === 'specific') {
        const listStr = document.getElementById('qc-sel-list')?.value || '1';
        config.list = listStr.split(',').map(s => parseInt(s.trim())).filter(n => !isNaN(n));
    } else if (selType === 'time_range') {
        config.time_range = [
            parseFloat(document.getElementById('qc-sel-time-start')?.value || '0'),
            parseFloat(document.getElementById('qc-sel-time-end')?.value || '5')
        ];
    }

    return config;
}

/**
 * Run the Query → Calculate observable flow from the GUI.
 */
async function runObservableCalculation() {
    if (!selectedSimRunId) {
        alert('Please search and select a simulation run first.');
        return;
    }

    const observable = buildQCObservableConfig();
    if (!observable) {
        alert('Please select an observable type.');
        return;
    }

    const selection = buildQCSelectionConfig();

    const statusEl = document.getElementById('qc-calc-status');
    if (statusEl) {
        statusEl.style.display = 'block';
        statusEl.innerHTML = '<span style="color:#17a2b8;">Submitting calculation...</span>';
    }

    try {
        const result = await calculateObservable(selectedSimRunId, observable, selection);
        obsCalcTrackingId = result.tracking_id;

        if (statusEl) {
            statusEl.innerHTML = `<span style="color:#17a2b8;">Running... (${result.tracking_id})</span>`;
        }

        // Start polling
        if (obsCalcPollInterval) clearInterval(obsCalcPollInterval);
        obsCalcPollInterval = setInterval(async () => {
            try {
                const resp = await fetch(`${API_BASE_URL}/api/status/${obsCalcTrackingId}`);
                if (!resp.ok) return;
                const status = await resp.json();

                if (status.status === 'completed') {
                    clearInterval(obsCalcPollInterval);
                    obsCalcPollInterval = null;
                    const res = status.result || {};
                    if (statusEl) {
                        statusEl.innerHTML = `
                            <div style="color:#28a745; font-weight:bold;">Completed</div>
                            <div style="font-size:12px; margin-top:4px;">
                                <div>Observable Run: <code>${res.obs_run_id || '—'}</code></div>
                                <div>Directory: <code>${res.obs_run_dir || '—'}</code></div>
                            </div>
                            <button class="btn btn-success" style="margin-top:8px; padding:6px 12px; font-size:12px;"
                                    onclick="loadAndDisplayObsResults('${res.obs_run_id}')">
                                View Results
                            </button>
                        `;
                    }
                } else if (status.status === 'failed') {
                    clearInterval(obsCalcPollInterval);
                    obsCalcPollInterval = null;
                    if (statusEl) {
                        statusEl.innerHTML = `<div style="color:#dc3545;">Failed: ${status.last_message}</div>`;
                    }
                } else if (statusEl) {
                    statusEl.innerHTML = `<span style="color:#17a2b8;">${status.last_message}</span>`;
                }
            } catch (e) {
                console.error('Poll error:', e);
            }
        }, 1000);

    } catch (e) {
        if (statusEl) {
            statusEl.innerHTML = `<div style="color:#dc3545;">Error: ${e.message}</div>`;
        }
    }
}

/**
 * Fetch and display observable results in the results panel.
 */
async function loadAndDisplayObsResults(obsRunId) {
    const container = document.getElementById('qc-results-display');
    if (!container) return;

    container.style.display = 'block';
    container.innerHTML = '<em>Loading results...</em>';

    try {
        const data = await getObservableResults(obsRunId);
        const indices = data.data?.indices || [];
        const values = data.data?.values || [];
        const times = data.data?.times || null;

        let html = `<h4 style="margin:0 0 8px 0;">Results: ${obsRunId}</h4>`;
        html += `<div style="font-size:12px; color:#666; margin-bottom:8px;">`;
        html += `${indices.length} data point(s)`;
        if (data.catalog_entry?.observable?.type) {
            html += ` &middot; ${data.catalog_entry.observable.type}`;
        }
        html += `</div>`;

        // Simple table display
        html += '<div style="max-height:300px; overflow-y:auto;">';
        html += '<table style="width:100%; font-size:12px; border-collapse:collapse;">';
        html += '<thead><tr style="background:#f0f0f0;">';
        html += '<th style="padding:4px 8px; text-align:left;">Index</th>';
        if (times) html += '<th style="padding:4px 8px; text-align:left;">Time</th>';
        html += '<th style="padding:4px 8px; text-align:left;">Value</th>';
        html += '</tr></thead><tbody>';

        for (let i = 0; i < indices.length; i++) {
            html += '<tr style="border-bottom:1px solid #eee;">';
            html += `<td style="padding:4px 8px;">${indices[i]}</td>`;
            if (times) html += `<td style="padding:4px 8px;">${times[i]?.toFixed(4) ?? '—'}</td>`;

            const val = values[i];
            let valStr;
            if (typeof val === 'object' && val !== null) {
                if (val.real !== undefined) {
                    valStr = `${val.real.toFixed(8)} + ${val.imag.toFixed(8)}i`;
                } else if (Array.isArray(val)) {
                    valStr = `[${val.length} elements]`;
                } else {
                    valStr = JSON.stringify(val);
                }
            } else {
                valStr = typeof val === 'number' ? val.toFixed(8) : String(val);
            }
            html += `<td style="padding:4px 8px; font-family:monospace;">${valStr}</td>`;
            html += '</tr>';
        }

        html += '</tbody></table></div>';
        container.innerHTML = html;

    } catch (e) {
        container.innerHTML = `<div style="color:#dc3545;">Error loading results: ${e.message}</div>`;
    }
}

/**
 * Search simulations and populate the results table.
 */
async function searchSimulations() {
    const statusEl = document.getElementById('qc-search-status');
    const resultsEl = document.getElementById('qc-search-results');
    if (!resultsEl) return;

    if (statusEl) {
        statusEl.style.display = 'block';
        statusEl.innerHTML = '<em>Searching...</em>';
    }

    // Collect filter values from search form
    const filters = {};

    // Core dropdowns
    const coreFields = [
        { id: 'qc-filter-algorithm', key: 'algorithm' },
        { id: 'qc-filter-system_type', key: 'system_type' },
        { id: 'qc-filter-model_name', key: 'model_name' },
        { id: 'qc-filter-status', key: 'status' },
        { id: 'qc-filter-S', key: 'S' },
        { id: 'qc-filter-dtype', key: 'dtype' },
    ];
    for (const f of coreFields) {
        const el = document.getElementById(f.id);
        if (el && el.value) filters[f.key] = el.value;
    }

    // N with comparison operator
    const nVal = document.getElementById('qc-filter-N')?.value;
    if (nVal) {
        const nOp = document.getElementById('qc-filter-N-op')?.value || '=';
        const nKey = nOp === '=' ? 'N' : 'N' + nOp;
        filters[nKey] = nVal;
    }

    // Dynamic algorithm params (prefixed algo_)
    _collectDynamicParams('qc-algo-params-inner', 'algo_', filters);

    // Dynamic model params (prefixed model_)
    _collectDynamicParams('qc-model-params-inner', 'model_', filters);

    // State filters
    const stateKind = document.getElementById('qc-filter-state_kind')?.value;
    if (stateKind) filters['state_kind'] = stateKind;
    const stateName = document.getElementById('qc-filter-state_name')?.value;
    if (stateName) filters['state_name'] = stateName;

    // Dynamic state params (prefixed state_)
    _collectDynamicParams('qc-state-params-inner', 'state_', filters);

    try {
        const data = await querySimulations(filters);
        const results = data.results || [];

        if (statusEl) {
            statusEl.innerHTML = `Found <strong>${results.length}</strong> simulation(s)`;
        }

        if (results.length === 0) {
            resultsEl.innerHTML = '<em style="color:#666;">No simulations match your filters.</em>';
            return;
        }

        let html = '<table style="width:100%; font-size:12px; border-collapse:collapse;">';
        html += '<thead><tr style="background:#f0f0f0;">';
        html += '<th style="padding:6px;">Select</th>';
        html += '<th style="padding:6px;">Run ID</th>';
        html += '<th style="padding:6px;">Algorithm</th>';
        html += '<th style="padding:6px;">Model</th>';
        html += '<th style="padding:6px;">N</th>';
        html += '<th style="padding:6px;">State</th>';
        html += '<th style="padding:6px;">Key Params</th>';
        html += '<th style="padding:6px;">Status</th>';
        html += '</tr></thead><tbody>';

        for (const r of results) {
            const core = r.core || {};
            const model = r.model || {};
            const state = r.state || {};
            const algoParams = r.algorithm_params || {};
            const runId = r.run_id || '—';

            // Summarize key params (top 3 algo + model params)
            const paramParts = [];
            for (const [k, v] of Object.entries(algoParams).slice(0, 2)) {
                paramParts.push(`${k}=${v}`);
            }
            if (model.params) {
                for (const [k, v] of Object.entries(model.params).slice(0, 2)) {
                    paramParts.push(`${k}=${v}`);
                }
            }
            const paramStr = paramParts.join(', ') || '—';
            const stateStr = state.name || state.kind || '—';

            html += `<tr style="border-bottom:1px solid #eee; cursor:pointer;" onclick="selectSimRun('${runId}', this)">`;
            html += `<td style="padding:6px;"><input type="radio" name="sim-select" value="${runId}"></td>`;
            html += `<td style="padding:6px; font-family:monospace; font-size:11px;">${runId}</td>`;
            html += `<td style="padding:6px;">${core.algorithm || '—'}</td>`;
            html += `<td style="padding:6px;">${model.name || '—'}</td>`;
            html += `<td style="padding:6px;">${core.N || core.N_spins || '—'}</td>`;
            html += `<td style="padding:6px;">${stateStr}</td>`;
            html += `<td style="padding:6px; font-size:11px; color:#666;">${paramStr}</td>`;
            html += `<td style="padding:6px;">${r.status || '—'}</td>`;
            html += '</tr>';
        }

        html += '</tbody></table>';
        resultsEl.innerHTML = html;

    } catch (e) {
        if (statusEl) {
            statusEl.innerHTML = `<span style="color:#dc3545;">Error: ${e.message}</span>`;
        }
        resultsEl.innerHTML = '';
    }
}

/**
 * Handle selection of a simulation run from search results.
 */
function selectSimRun(runId, rowEl) {
    selectedSimRunId = runId;

    // Highlight selected row
    const table = rowEl?.closest('table');
    if (table) {
        table.querySelectorAll('tr').forEach(tr => tr.style.background = '');
        rowEl.style.background = '#d4edda';
    }

    // Check the radio button
    const radio = rowEl?.querySelector('input[type="radio"]');
    if (radio) radio.checked = true;

    // Update status display
    const el = document.getElementById('qc-selected-run');
    if (el) {
        el.style.display = 'block';
        el.innerHTML = `Selected: <code>${runId}</code>`;
    }
}

// ============================================================================
// CATALOG INFO: Fetching & Dynamic Filter Building
// ============================================================================

/**
 * Fetch simulation catalog metadata for dynamic cascading dropdowns.
 * Stores result in window.TNCatalogInfo.
 */
async function fetchCatalogInfo() {
    const response = await fetch(`${API_BASE_URL}/api/catalog-info`);
    if (!response.ok) throw new Error(`Failed: ${response.statusText}`);
    const data = await response.json();
    window.TNCatalogInfo = data;
    populateDynamicQueryFilters(data);
    return data;
}

/**
 * Fetch observable catalog metadata for browse section dropdowns.
 * Stores result in window.TNObservableCatalogInfo.
 */
async function fetchObservableCatalogInfo() {
    const response = await fetch(`${API_BASE_URL}/api/observable-catalog-info`);
    if (!response.ok) throw new Error(`Failed: ${response.statusText}`);
    const data = await response.json();
    window.TNObservableCatalogInfo = data;
    populateObsBrowserDropdowns(data);
    return data;
}

/**
 * Refresh catalog info and repopulate all dropdowns.
 */
async function refreshCatalogInfo() {
    try {
        await fetchCatalogInfo();
        await fetchObservableCatalogInfo();
    } catch (e) {
        console.warn('Refresh failed:', e.message);
    }
}

/**
 * Populate Step 1 filter dropdowns from catalog metadata.
 */
function populateDynamicQueryFilters(info) {
    if (!info) return;

    // Algorithm dropdown
    _populateSelect('qc-filter-algorithm', Object.keys(info.algorithms || {}));

    // System type
    _populateSelect('qc-filter-system_type', (info.core || {}).system_type || []);

    // Model name (replace text input with select options)
    _populateSelect('qc-filter-model_name', Object.keys(info.models || {}));

    // S values
    _populateSelect('qc-filter-S', (info.core || {}).S || []);

    // dtype values
    _populateSelect('qc-filter-dtype', (info.core || {}).dtype || []);

    // State kind
    _populateSelect('qc-filter-state_kind', Object.keys(info.states_by_kind || {}));
}

/**
 * Populate a <select> element with options, keeping "Any" as first option.
 */
function _populateSelect(elementId, values) {
    const el = document.getElementById(elementId);
    if (!el) return;
    const current = el.value;
    el.innerHTML = '<option value="">Any</option>';
    for (const v of values) {
        el.innerHTML += `<option value="${v}">${v}</option>`;
    }
    if (current) el.value = current;
}

// ============================================================================
// CASCADING FILTER HANDLERS
// ============================================================================

/**
 * When algorithm is selected, show its specific parameter filters.
 */
function onQCAlgorithmChange() {
    const algo = document.getElementById('qc-filter-algorithm')?.value;
    const container = document.getElementById('qc-algo-params');
    const inner = document.getElementById('qc-algo-params-inner');
    if (!container || !inner) return;

    if (!algo || !window.TNCatalogInfo?.algorithms?.[algo]) {
        container.style.display = 'none';
        inner.innerHTML = '';
        return;
    }

    const params = window.TNCatalogInfo.algorithms[algo];
    inner.innerHTML = '';
    for (const [paramName, values] of Object.entries(params)) {
        inner.innerHTML += _buildParamFilter('algo', paramName, values);
    }
    container.style.display = inner.innerHTML ? 'block' : 'none';
}

/**
 * When model is selected, show its specific parameter filters.
 */
function onQCModelChange() {
    const model = document.getElementById('qc-filter-model_name')?.value;
    const container = document.getElementById('qc-model-params');
    const inner = document.getElementById('qc-model-params-inner');
    if (!container || !inner) return;

    if (!model || !window.TNCatalogInfo?.models?.[model]) {
        container.style.display = 'none';
        inner.innerHTML = '';
        return;
    }

    const modelInfo = window.TNCatalogInfo.models[model];
    const params = modelInfo.params || {};
    inner.innerHTML = '';
    for (const [paramName, values] of Object.entries(params)) {
        inner.innerHTML += _buildParamFilter('model', paramName, values);
    }
    container.style.display = inner.innerHTML ? 'block' : 'none';
}

/**
 * When state kind is selected, populate state names and show state param filters.
 */
function onQCStateKindChange() {
    const kind = document.getElementById('qc-filter-state_kind')?.value;
    const nameSelect = document.getElementById('qc-filter-state_name');
    const container = document.getElementById('qc-state-params');
    const inner = document.getElementById('qc-state-params-inner');

    if (!kind || !window.TNCatalogInfo?.states_by_kind?.[kind]) {
        if (nameSelect) { nameSelect.innerHTML = '<option value="">Any</option>'; }
        if (container) container.style.display = 'none';
        if (inner) inner.innerHTML = '';
        return;
    }

    const stateInfo = window.TNCatalogInfo.states_by_kind[kind];

    // Populate state names (for prebuilt)
    if (nameSelect) {
        const names = Object.keys(stateInfo.names || {});
        nameSelect.innerHTML = '<option value="">Any</option>';
        for (const n of names) {
            nameSelect.innerHTML += `<option value="${n}">${n}</option>`;
        }
    }

    // Show kind-level params (for random/custom)
    if (inner && container) {
        const params = stateInfo.params || {};
        inner.innerHTML = '';
        for (const [paramName, values] of Object.entries(params)) {
            inner.innerHTML += _buildParamFilter('state', paramName, values);
        }
        container.style.display = inner.innerHTML ? 'block' : 'none';
    }
}

/**
 * Build a single parameter filter row.
 * For numeric values: operator dropdown + number input.
 * For string values: select dropdown.
 */
function _buildParamFilter(prefix, paramName, values) {
    const isNumeric = values.length > 0 && values.every(v => typeof v === 'number');
    const displayName = paramName.replace(/_/g, ' ');

    if (isNumeric) {
        const sorted = [...values].sort((a, b) => a - b);
        const min = sorted[0];
        const max = sorted[sorted.length - 1];
        return `
            <div class="form-group" style="min-width:140px; flex:1;">
                <label style="font-size:11px;">${displayName} <span style="color:#999; font-size:10px;">[${min}–${max}]</span></label>
                <div style="display:flex; gap:4px;">
                    <select data-dyn-op="${prefix}_${paramName}" style="width:50px; font-size:11px; padding:4px;">
                        <option value="=">=</option>
                        <option value="_gte">≥</option>
                        <option value="_gt">&gt;</option>
                        <option value="_lte">≤</option>
                        <option value="_lt">&lt;</option>
                    </select>
                    <input type="number" data-dyn-val="${prefix}_${paramName}" placeholder="Any" style="flex:1; font-size:11px; padding:4px;">
                </div>
            </div>`;
    } else {
        let options = '<option value="">Any</option>';
        for (const v of values) {
            options += `<option value="${v}">${v}</option>`;
        }
        return `
            <div class="form-group" style="min-width:120px; flex:1;">
                <label style="font-size:11px;">${displayName}</label>
                <select data-dyn-val="${prefix}_${paramName}" style="font-size:11px; padding:4px;">
                    ${options}
                </select>
            </div>`;
    }
}

/**
 * Collect dynamic parameter filter values from a container.
 * Reads data-dyn-val and data-dyn-op attributes to build filter keys.
 */
function _collectDynamicParams(containerId, prefix, filters) {
    const container = document.getElementById(containerId);
    if (!container) return;

    // Collect all value elements
    const valEls = container.querySelectorAll('[data-dyn-val]');
    for (const el of valEls) {
        const val = el.value;
        if (!val) continue;

        const rawKey = el.getAttribute('data-dyn-val'); // e.g. "algo_chi_max"
        // Check for operator
        const opEl = container.querySelector(`[data-dyn-op="${rawKey}"]`);
        const op = opEl?.value || '=';
        const filterKey = op === '=' ? rawKey : rawKey + op;
        filters[filterKey] = val;
    }
}

// ============================================================================
// OBSERVABLE CATALOG BROWSER
// ============================================================================

/**
 * Populate Browse Observable section dropdowns from observable catalog metadata.
 */
function populateObsBrowserDropdowns(info) {
    if (!info) return;
    _populateSelect('obs-browse-type', info.observable_types || []);
    _populateSelect('obs-browse-sim-algo', info.sim_algorithms || []);
    _populateSelect('obs-browse-sim-model', info.sim_models || []);
    _populateSelect('obs-browse-selection', info.selection_types || []);
}

/**
 * When observable type is selected in browser, show type-specific param filters.
 */
function onObsBrowseTypeChange() {
    const obsType = document.getElementById('obs-browse-type')?.value;
    const container = document.getElementById('obs-browse-params');
    const inner = document.getElementById('obs-browse-params-inner');
    if (!container || !inner) return;

    if (!obsType || !window.TNObservableCatalogInfo?.observable_params?.[obsType]) {
        container.style.display = 'none';
        inner.innerHTML = '';
        return;
    }

    const params = window.TNObservableCatalogInfo.observable_params[obsType];
    inner.innerHTML = '';
    for (const [paramName, values] of Object.entries(params)) {
        inner.innerHTML += _buildParamFilter('observable', paramName, values);
    }
    container.style.display = inner.innerHTML ? 'block' : 'none';
}

/**
 * Browse observable catalog with current filters.
 */
async function browseObservables() {
    const statusEl = document.getElementById('obs-browse-status-msg');
    const resultsEl = document.getElementById('obs-browse-results');
    if (!resultsEl) return;

    if (statusEl) {
        statusEl.style.display = 'block';
        statusEl.innerHTML = '<em>Searching observable catalog...</em>';
    }

    // Collect filters
    const filters = {};
    const fields = [
        { id: 'obs-browse-type', key: 'observable_type' },
        { id: 'obs-browse-sim-algo', key: 'sim_algorithm' },
        { id: 'obs-browse-sim-model', key: 'sim_model_name' },
        { id: 'obs-browse-selection', key: 'analysis_selection_type' },
        { id: 'obs-browse-status', key: 'status' },
    ];
    for (const f of fields) {
        const el = document.getElementById(f.id);
        if (el && el.value) filters[f.key] = el.value;
    }

    // Dynamic observable params
    _collectDynamicParams('obs-browse-params-inner', 'observable', filters);

    try {
        const data = await queryObservables(filters);
        const results = data.results || [];

        if (statusEl) {
            statusEl.innerHTML = `Found <strong>${results.length}</strong> observable calculation(s)`;
        }

        if (results.length === 0) {
            resultsEl.innerHTML = '<em style="color:#666;">No observable calculations match your filters.</em>';
            return;
        }

        let html = '<table style="width:100%; font-size:12px; border-collapse:collapse;">';
        html += '<thead><tr style="background:#f0f0f0;">';
        html += '<th style="padding:6px;">Obs Run ID</th>';
        html += '<th style="padding:6px;">Observable</th>';
        html += '<th style="padding:6px;">Sim Algorithm</th>';
        html += '<th style="padding:6px;">Model</th>';
        html += '<th style="padding:6px;">N</th>';
        html += '<th style="padding:6px;">Selection</th>';
        html += '<th style="padding:6px;">Status</th>';
        html += '<th style="padding:6px;">View</th>';
        html += '</tr></thead><tbody>';

        for (const r of results) {
            const obs = r.observable || {};
            const sim = r.simulation || {};
            const simCore = sim.core || {};
            const simModel = sim.model || {};
            const analysis = r.analysis_params || {};
            const obsRunId = r.obs_run_id || '—';

            // Extract selection type from analysis_params
            let selType = '—';
            for (const key of ['sweep_selection', 'step_selection', 'state_selection']) {
                if (analysis[key]) { selType = analysis[key].type || '—'; break; }
            }

            // Observable params summary
            const obsParams = obs.params || {};
            const obsParamStr = Object.entries(obsParams).map(([k,v]) => `${k}=${v}`).join(', ');
            const obsLabel = obs.type + (obsParamStr ? ` (${obsParamStr})` : '');

            html += `<tr style="border-bottom:1px solid #eee;">`;
            html += `<td style="padding:6px; font-family:monospace; font-size:11px;">${obsRunId}</td>`;
            html += `<td style="padding:6px;">${obsLabel}</td>`;
            html += `<td style="padding:6px;">${simCore.algorithm || '—'}</td>`;
            html += `<td style="padding:6px;">${simModel.name || '—'}</td>`;
            html += `<td style="padding:6px;">${simCore.N || simCore.N_spins || '—'}</td>`;
            html += `<td style="padding:6px;">${selType}</td>`;
            html += `<td style="padding:6px;">${r.status || '—'}</td>`;
            html += `<td style="padding:6px;"><button style="font-size:11px; padding:2px 8px; cursor:pointer;" onclick="loadAndDisplayObsResults('${obsRunId}')">View</button></td>`;
            html += '</tr>';
        }

        html += '</tbody></table>';
        resultsEl.innerHTML = html;

    } catch (e) {
        if (statusEl) {
            statusEl.innerHTML = `<span style="color:#dc3545;">Error: ${e.message}</span>`;
        }
        resultsEl.innerHTML = '';
    }
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

// New query & calculate exports
window.querySimulations = querySimulations;
window.queryObservables = queryObservables;
window.getSimulationResults = getSimulationResults;
window.getObservableResults = getObservableResults;
window.calculateObservable = calculateObservable;
window.fetchObservablesRegistry = fetchObservablesRegistry;
window.searchSimulations = searchSimulations;
window.selectSimRun = selectSimRun;
window.runObservableCalculation = runObservableCalculation;
window.loadAndDisplayObsResults = loadAndDisplayObsResults;
window.populateObservableSelector = populateObservableSelector;
window.renderObservableParams = renderObservableParams;
window.buildQCObservableConfig = buildQCObservableConfig;
window.buildQCSelectionConfig = buildQCSelectionConfig;

// Dynamic query filter exports
window.fetchCatalogInfo = fetchCatalogInfo;
window.fetchObservableCatalogInfo = fetchObservableCatalogInfo;
window.refreshCatalogInfo = refreshCatalogInfo;
window.populateDynamicQueryFilters = populateDynamicQueryFilters;
window.onQCAlgorithmChange = onQCAlgorithmChange;
window.onQCModelChange = onQCModelChange;
window.onQCStateKindChange = onQCStateKindChange;
window.onObsBrowseTypeChange = onObsBrowseTypeChange;
window.browseObservables = browseObservables;
