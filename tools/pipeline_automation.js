// ============================================================================
// PIPELINE AUTOMATION - CLIENT-SIDE JAVASCRIPT
// ============================================================================
//
// Add this script to your config_builder_v4.html to enable single-click
// pipeline execution.
//
// USAGE:
//   Add to HTML: <script src="pipeline_automation.js"></script>
//
// Or inline at the end of config_builder_v4.html
//
// ============================================================================

// Server configuration
const API_BASE_URL = 'http://localhost:8080';

// Track current run
let currentTrackingId = null;
let statusCheckInterval = null;

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
        const config = buildConfig();  // This function exists in config_builder_v4.html
        const mode = currentMode;      // This variable exists in config_builder_v4.html
        
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

// If used inline in HTML, these functions are available globally
window.runPipeline = runPipeline;
window.checkServerStatus = checkServerStatus;
