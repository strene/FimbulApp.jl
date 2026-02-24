"""
FimbulApp web application entry point.

Starts a Genie.jl web server with a reactive dashboard for configuring
and running geothermal simulations via Fimbul.jl.

    julia app.jl              # start on default port 8000
    julia app.jl --port=9000  # start on custom port
"""

using Genie, Genie.Renderer.Html, Genie.Requests
using JSON3
using Dates

# Load FimbulApp module
using FimbulApp
using FimbulApp.CaseParameters
using FimbulApp.Simulation

# ---------------------------------------------------------------------------
# Serve static files
# ---------------------------------------------------------------------------
const PUBLIC_DIR = joinpath(@__DIR__, "public")

# ---------------------------------------------------------------------------
# Routes
# ---------------------------------------------------------------------------

route("/") do
    html(dashboard_html())
end

route("/css/style.css") do
    Genie.Renderer.respond(
        read(joinpath(PUBLIC_DIR, "css", "style.css"), String),
        :css
    )
end

route("/js/vue.global.prod.js") do
    Genie.Renderer.respond(
        read(joinpath(PUBLIC_DIR, "js", "vue.global.prod.js"), String),
        :javascript
    )
end

route("/api/defaults/:case_type") do
    ct = parse_case_type(payload(:case_type))
    isnothing(ct) && return Genie.Renderer.respond("Invalid case type", :text, status=400)
    params = default_params(ct)
    d = CaseParameters.params_to_dict(params)
    fields = CaseParameters.param_fields(ct)
    meta = Dict{Symbol, Any}()
    for f in fields
        m = CaseParameters.param_metadata(f)
        if !isnothing(m)
            meta[f] = m
        end
    end
    return Genie.Renderer.Json.json(Dict(
        :case_type => string(ct),
        :label => CaseParameters.CASE_LABELS[ct],
        :description => CaseParameters.CASE_DESCRIPTIONS[ct],
        :category => string(CaseParameters.CASE_CATEGORIES[ct]),
        :params => d,
        :metadata => meta,
    ))
end

route("/api/validate", method=POST) do
    data = jsonpayload()
    isnothing(data) && return Genie.Renderer.respond("Invalid JSON", :text, status=400)
    ct = parse_case_type(get(data, "case_type", ""))
    isnothing(ct) && return Genie.Renderer.respond("Invalid case type", :text, status=400)
    params = CaseParameters.dict_to_params(ct, data["params"])
    errors = validate_params(params)
    return Genie.Renderer.Json.json(Dict(
        :valid => isempty(errors),
        :errors => [Dict(:field => string(e[1]), :message => e[2]) for e in errors],
    ))
end

route("/api/simulate", method=POST) do
    data = jsonpayload()
    isnothing(data) && return Genie.Renderer.respond("Invalid JSON", :text, status=400)
    ct = parse_case_type(get(data, "case_type", ""))
    isnothing(ct) && return Genie.Renderer.respond("Invalid case type", :text, status=400)
    params = CaseParameters.dict_to_params(ct, data["params"])
    result = run_simulation(ct, params)
    return Genie.Renderer.Json.json(Dict(
        :status => string(result.status),
        :message => result.message,
        :well_data => result.well_data,
        :timestamps => result.timestamps,
        :reservoir_vars => result.reservoir_vars,
        :num_steps => result.num_steps,
    ))
end

route("/api/reservoir_image/:var/:step") do
    var = payload(:var)
    step_str = payload(:step)
    step = tryparse(Int, step_str)
    isnothing(step) && return Genie.Renderer.respond("Invalid step", :text, status=400)
    step < 0 && return Genie.Renderer.respond("Step must be non-negative", :text, status=400)
    step += 1  # Convert 0-indexed (frontend) to 1-indexed (Julia)
    delta = get(Genie.Requests.getpayload(), "delta", "false") == "true"
    img = render_reservoir_image(var, step; delta=delta)
    isempty(img) && return Genie.Renderer.respond("", :text, status=404)
    return Genie.Renderer.respond(img, :text)
end

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

function parse_case_type(s::AbstractString)
    s = uppercase(strip(s))
    s == "DOUBLET" && return DOUBLET
    s == "EGS"     && return EGS
    s == "AGS"     && return AGS
    s == "ATES"    && return ATES
    s == "BTES"    && return BTES
    return nothing
end

# ---------------------------------------------------------------------------
# HTML Dashboard
# ---------------------------------------------------------------------------

function dashboard_html()
    """
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>FimbulApp – Geothermal Simulation Dashboard</title>
    <link rel="stylesheet" href="/css/style.css">
</head>
<body>
<div id="app">
    <!-- Header -->
    <header class="app-header">
        <div class="header-content">
            <h1 class="app-title">❄️ FimbulApp</h1>
            <p class="app-subtitle">Geothermal Energy Simulation Dashboard</p>
        </div>
    </header>

    <!-- Navigation: Case Type Selection -->
    <nav class="case-nav">
        <div class="nav-section">
            <span class="nav-label">Energy Production</span>
            <button class="case-btn" :class="{active: caseType === 'DOUBLET'}" @click="selectCase('DOUBLET')">
                Doublet
            </button>
            <button class="case-btn" :class="{active: caseType === 'EGS'}" @click="selectCase('EGS')">
                EGS
            </button>
            <button class="case-btn" :class="{active: caseType === 'AGS'}" @click="selectCase('AGS')">
                AGS
            </button>
        </div>
        <div class="nav-section">
            <span class="nav-label">Energy Storage</span>
            <button class="case-btn" :class="{active: caseType === 'ATES'}" @click="selectCase('ATES')">
                ATES
            </button>
            <button class="case-btn" :class="{active: caseType === 'BTES'}" @click="selectCase('BTES')">
                BTES
            </button>
        </div>
    </nav>

    <!-- Tab Bar -->
    <div class="tab-bar">
        <button class="tab-btn" :class="{active: activeTab === 'setup'}" @click="activeTab = 'setup'">
            ⚙️ Setup
        </button>
        <button class="tab-btn" :class="{active: activeTab === 'results', disabled: simStatus !== 'COMPLETED'}"
            :disabled="simStatus !== 'COMPLETED'"
            @click="activeTab = 'results'">
            📊 Results
        </button>
    </div>

    <!-- Main Content -->
    <main class="main-content">

        <!-- ============ SETUP TAB ============ -->
        <div v-show="activeTab === 'setup'">
            <!-- Case Description -->
            <section class="case-description" v-if="caseInfo">
                <h2>{{ caseInfo.label }}</h2>
                <p>{{ caseInfo.description }}</p>
            </section>

            <div class="content-grid">
                <!-- Parameter Panel -->
                <section class="panel param-panel">
                    <h3>⚙️ Parameters</h3>
                    <div class="param-list" v-if="caseInfo">
                        <div class="param-item" v-for="(meta, field) in caseInfo.metadata" :key="field">
                            <div class="param-header">
                                <label class="param-label" :title="meta.tooltip">
                                    {{ meta.label }}
                                    <span class="param-unit">[{{ meta.unit }}]</span>
                                </label>
                                <input class="param-input" type="number"
                                    :min="meta.min" :max="meta.max" :step="meta.step"
                                    v-model.number="params[field]"
                                    @change="onParamChange">
                            </div>
                            <input class="param-slider" type="range"
                                :min="meta.min" :max="meta.max" :step="meta.step"
                                v-model.number="params[field]"
                                @input="onParamChange">
                            <div class="param-error" v-if="paramErrors[field]">
                                {{ paramErrors[field] }}
                            </div>
                        </div>
                    </div>
                    <div class="param-actions">
                        <button class="btn btn-reset" @click="resetDefaults">↺ Reset Defaults</button>
                    </div>
                </section>

                <!-- Visualization / Results Panel -->
                <section class="panel results-panel">
                    <h3>📊 Simulation</h3>

                    <div class="sim-controls">
                        <button class="btn btn-run" @click="runSimulation"
                            :disabled="simStatus === 'RUNNING' || !isValid">
                            <span v-if="simStatus === 'RUNNING'">⏳ Running...</span>
                            <span v-else>▶ Run Simulation</span>
                        </button>
                    </div>

                    <div class="sim-status" v-if="simMessage">
                        <div :class="'status-' + simStatus.toLowerCase()">
                            {{ simMessage }}
                        </div>
                    </div>

                    <!-- Parameter Summary -->
                    <div class="summary-section" v-if="caseInfo">
                        <h4>Current Configuration</h4>
                        <table class="summary-table">
                            <tr v-for="(meta, field) in caseInfo.metadata" :key="field">
                                <td class="summary-label">{{ meta.label }}</td>
                                <td class="summary-value">{{ formatValue(params[field]) }}</td>
                                <td class="summary-unit">{{ meta.unit }}</td>
                            </tr>
                        </table>
                    </div>
                </section>
            </div>
        </div>

        <!-- ============ RESULTS TAB ============ -->
        <div v-show="activeTab === 'results'" v-if="simStatus === 'COMPLETED'">
            <div class="results-grid">
                <!-- Reservoir States Section -->
                <section class="panel reservoir-panel">
                    <h3>🗺️ Reservoir States</h3>
                    <div v-if="reservoirVars.length > 0">
                        <div class="result-controls">
                            <label class="control-label">Variable:</label>
                            <select class="control-select" v-model="selectedReservoirVar" @change="fetchReservoirImage">
                                <option v-for="v in reservoirVars" :key="v" :value="v">{{ v }}</option>
                            </select>
                        </div>
                        <div class="playback-controls">
                            <button class="btn btn-playback" @click="firstStep" :disabled="currentStep <= 0">⏮</button>
                            <button class="btn btn-playback" @click="prevStep" :disabled="currentStep <= 0">◀</button>
                            <button class="btn btn-playback" @click="nextStep" :disabled="currentStep >= totalSteps - 1">▶</button>
                            <button class="btn btn-playback" @click="lastStep" :disabled="currentStep >= totalSteps - 1">⏭</button>
                            <input type="range" class="step-slider" min="0" :max="totalSteps - 1"
                                v-model.number="currentStep" @input="fetchReservoirImage(); drawWellPlot()">
                            <span class="step-label">Step {{ currentStep + 1 }} / {{ totalSteps }}</span>
                        </div>
                        <div class="result-controls">
                            <label class="control-label">
                                <input type="checkbox" v-model="showDelta" @change="fetchReservoirImage">
                                Show difference from initial state
                            </label>
                        </div>
                        <div class="reservoir-canvas-wrapper">
                            <div v-if="imageLoading" class="loading-indicator">⏳ Rendering image...</div>
                            <img v-if="currentImageSrc"
                                :src="currentImageSrc"
                                class="reservoir-image" alt="Reservoir state visualization" />
                            <div v-if="!currentImageSrc && !imageLoading" class="no-data">
                                Select a variable and step to view the reservoir state.
                            </div>
                        </div>
                    </div>
                    <div v-else class="no-data">No reservoir state data available.</div>
                </section>

                <!-- Well Output Section -->
                <section class="panel well-panel">
                    <h3>🛢️ Well Output</h3>
                    <div v-if="wellNames.length > 0">
                        <div class="result-controls">
                            <label class="control-label">Well:</label>
                            <select class="control-select" v-model="selectedWell" @change="drawWellPlot">
                                <option v-for="w in wellNames" :key="w" :value="w">{{ w }}</option>
                            </select>
                        </div>
                        <div class="result-controls" v-if="wellVars.length > 0">
                            <label class="control-label">Variable:</label>
                            <select class="control-select" v-model="selectedWellVar" @change="drawWellPlot">
                                <option v-for="v in wellVars" :key="v" :value="v">{{ v }}</option>
                            </select>
                        </div>
                        <div class="well-canvas-wrapper">
                            <canvas ref="wellCanvas" id="well-canvas" width="560" height="360"></canvas>
                        </div>
                    </div>
                    <div v-else class="no-data">No well output data available.</div>
                </section>
            </div>
        </div>

    </main>

    <!-- Footer -->
    <footer class="app-footer">
        <p>
            Powered by <a href="https://github.com/sintefmath/Fimbul.jl" target="_blank">Fimbul.jl</a>
            &amp; <a href="https://genieframework.com" target="_blank">Genie.jl</a>
        </p>
    </footer>
</div>

<script src="/js/vue.global.prod.js"></script>
<script>
const { createApp, ref, reactive, computed, watch, onMounted, nextTick } = Vue;

createApp({
    setup() {
        const caseType = ref('DOUBLET');
        const caseInfo = ref(null);
        const params = reactive({});
        const paramErrors = reactive({});
        const simStatus = ref('IDLE');
        const simMessage = ref('');
        const isValid = ref(true);
        const activeTab = ref('setup');

        // Results data
        const simResults = ref(null);
        const reservoirVars = ref([]);
        const selectedReservoirVar = ref('');
        const currentStep = ref(0);
        const totalSteps = ref(0);
        const showDelta = ref(false);
        const currentImageSrc = ref('');
        const imageLoading = ref(false);
        const imageCache = {};

        const wellNames = ref([]);
        const selectedWell = ref('');
        const wellVars = ref([]);
        const selectedWellVar = ref('');

        // Canvas refs
        const wellCanvas = ref(null);

        async function loadCaseDefaults(ct) {
            try {
                const resp = await fetch('/api/defaults/' + ct);
                const data = await resp.json();
                caseInfo.value = data;
                // Clear and set params
                Object.keys(params).forEach(k => delete params[k]);
                Object.assign(params, data.params);
                // Clear errors
                Object.keys(paramErrors).forEach(k => delete paramErrors[k]);
                simStatus.value = 'IDLE';
                simMessage.value = '';
            } catch (e) {
                console.error('Failed to load case defaults:', e);
            }
        }

        function selectCase(ct) {
            caseType.value = ct;
            loadCaseDefaults(ct);
        }

        async function onParamChange() {
            try {
                const resp = await fetch('/api/validate', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({
                        case_type: caseType.value,
                        params: { ...params }
                    })
                });
                const data = await resp.json();
                Object.keys(paramErrors).forEach(k => delete paramErrors[k]);
                if (!data.valid) {
                    data.errors.forEach(e => {
                        paramErrors[e.field] = e.message;
                    });
                }
                isValid.value = data.valid;
            } catch (e) {
                console.error('Validation error:', e);
            }
        }

        function resetDefaults() {
            loadCaseDefaults(caseType.value);
        }

        async function runSimulation() {
            simStatus.value = 'RUNNING';
            simMessage.value = 'Setting up and running simulation...';
            try {
                const resp = await fetch('/api/simulate', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({
                        case_type: caseType.value,
                        params: { ...params }
                    })
                });
                const data = await resp.json();
                simStatus.value = data.status;
                simMessage.value = data.message;
                if (data.status === 'COMPLETED') {
                    simResults.value = data;
                    populateResults(data);
                }
            } catch (e) {
                simStatus.value = 'FAILED';
                simMessage.value = 'Request failed: ' + e.message;
            }
        }

        function populateResults(data) {
            // Reservoir variables and step count from server
            const vars = data.reservoir_vars || [];
            reservoirVars.value = vars;
            selectedReservoirVar.value = vars.length > 0 ? vars[0] : '';
            totalSteps.value = data.num_steps || 0;
            currentStep.value = 0;
            currentImageSrc.value = '';
            // Clear client-side image cache
            Object.keys(imageCache).forEach(k => delete imageCache[k]);

            // Well data
            const wd = data.well_data || {};
            const names = Object.keys(wd);
            wellNames.value = names;
            selectedWell.value = names.length > 0 ? names[0] : '';
            if (names.length > 0) {
                const wdata = wd[names[0]];
                const wvars = Object.keys(wdata);
                wellVars.value = wvars;
                selectedWellVar.value = wvars.length > 0 ? wvars[0] : '';
            } else {
                wellVars.value = [];
                selectedWellVar.value = '';
            }
            // Switch to results tab and draw after DOM update
            activeTab.value = 'results';
            nextTick(() => {
                fetchReservoirImage();
                drawWellPlot();
            });
        }

        // --- Lazy reservoir image fetching with client-side cache ---
        async function fetchReservoirImage() {
            const varName = selectedReservoirVar.value;
            const step = currentStep.value;
            const delta = showDelta.value;
            if (!varName || totalSteps.value === 0) return;

            const cacheKey = varName + ':' + step + ':' + delta;
            if (imageCache[cacheKey]) {
                currentImageSrc.value = imageCache[cacheKey];
                return;
            }

            imageLoading.value = true;
            try {
                const url = '/api/reservoir_image/' + encodeURIComponent(varName) + '/' + step + '?delta=' + delta;
                const resp = await fetch(url);
                if (resp.ok) {
                    const base64 = await resp.text();
                    if (base64) {
                        const dataUri = 'data:image/png;base64,' + base64;
                        imageCache[cacheKey] = dataUri;
                        // Only update if still on the same step/var/delta
                        if (selectedReservoirVar.value === varName && currentStep.value === step && showDelta.value === delta) {
                            currentImageSrc.value = dataUri;
                        }
                    }
                }
            } catch (e) {
                console.error('Failed to fetch reservoir image:', e);
            } finally {
                imageLoading.value = false;
            }
        }

        function firstStep() {
            if (currentStep.value > 0) {
                currentStep.value = 0;
                fetchReservoirImage();
                drawWellPlot();
            }
        }
        function lastStep() {
            if (currentStep.value < totalSteps.value - 1) {
                currentStep.value = totalSteps.value - 1;
                fetchReservoirImage();
                drawWellPlot();
            }
        }
        function prevStep() {
            if (currentStep.value > 0) {
                currentStep.value--;
                fetchReservoirImage();
                drawWellPlot();
            }
        }
        function nextStep() {
            if (currentStep.value < totalSteps.value - 1) {
                currentStep.value++;
                fetchReservoirImage();
                drawWellPlot();
            }
        }

        // --- Well output drawing ---
        function drawWellPlot() {
            const data = simResults.value;
            if (!data) return;
            const wname = selectedWell.value;
            const vname = selectedWellVar.value;
            if (!wname || !vname) return;
            const wd = (data.well_data || {})[wname];
            if (!wd) return;
            const yvals = wd[vname];
            if (!yvals || yvals.length === 0) return;
            const timestamps = data.timestamps || [];
            const xvals = timestamps.length === yvals.length ? timestamps : yvals.map((_, i) => i);

            const canvas = wellCanvas.value || document.getElementById('well-canvas');
            if (!canvas) return;
            const ctx = canvas.getContext('2d');
            const W = canvas.width;
            const H = canvas.height;
            ctx.clearRect(0, 0, W, H);

            // Margins
            const ml = 70, mr = 20, mt = 20, mb = 50;
            const pw = W - ml - mr;
            const ph = H - mt - mb;

            const xmin = Math.min(...xvals);
            const xmax = Math.max(...xvals);
            const ymin = Math.min(...yvals);
            const ymax = Math.max(...yvals);
            const xrange = xmax - xmin || 1;
            const yrange = ymax - ymin || 1;

            function toX(v) { return ml + ((v - xmin) / xrange) * pw; }
            function toY(v) { return mt + ph - ((v - ymin) / yrange) * ph; }

            // Grid & axes
            ctx.strokeStyle = '#e2e8f0';
            ctx.lineWidth = 1;
            const nTicks = 5;
            ctx.font = '11px sans-serif';
            ctx.fillStyle = '#64748b';
            ctx.textAlign = 'center';
            for (let i = 0; i <= nTicks; i++) {
                const xv = xmin + (i / nTicks) * xrange;
                const px = toX(xv);
                ctx.beginPath(); ctx.moveTo(px, mt); ctx.lineTo(px, mt + ph); ctx.stroke();
                ctx.fillText(xv.toFixed(1), px, H - mb + 18);
            }
            ctx.textAlign = 'right';
            for (let i = 0; i <= nTicks; i++) {
                const yv = ymin + (i / nTicks) * yrange;
                const py = toY(yv);
                ctx.beginPath(); ctx.moveTo(ml, py); ctx.lineTo(ml + pw, py); ctx.stroke();
                ctx.fillText(yv.toFixed(1), ml - 5, py + 4);
            }

            // Axes border
            ctx.strokeStyle = '#94a3b8';
            ctx.lineWidth = 1.5;
            ctx.beginPath();
            ctx.moveTo(ml, mt); ctx.lineTo(ml, mt + ph); ctx.lineTo(ml + pw, mt + ph);
            ctx.stroke();

            // Data line
            ctx.beginPath();
            ctx.strokeStyle = '#2563eb';
            ctx.lineWidth = 2;
            for (let i = 0; i < xvals.length; i++) {
                const px = toX(xvals[i]);
                const py = toY(yvals[i]);
                if (i === 0) ctx.moveTo(px, py);
                else ctx.lineTo(px, py);
            }
            ctx.stroke();

            // Axis labels
            ctx.fillStyle = '#1e293b';
            ctx.font = '12px sans-serif';
            ctx.textAlign = 'center';
            ctx.fillText('Time', ml + pw / 2, H - 5);
            ctx.save();
            ctx.translate(14, mt + ph / 2);
            ctx.rotate(-Math.PI / 2);
            ctx.fillText(vname, 0, 0);
            ctx.restore();

            // Dot for current reservoir timestep
            const stepIdx = currentStep.value;
            if (stepIdx >= 0 && stepIdx < xvals.length) {
                const dotX = toX(xvals[stepIdx]);
                const dotY = toY(yvals[stepIdx]);
                ctx.beginPath();
                ctx.arc(dotX, dotY, 5, 0, 2 * Math.PI);
                ctx.fillStyle = '#e11d48';
                ctx.fill();
                ctx.strokeStyle = '#fff';
                ctx.lineWidth = 1.5;
                ctx.stroke();
            }
        }

        // Update well variables when well changes
        watch(selectedWell, (wname) => {
            if (!simResults.value || !wname) return;
            const wd = (simResults.value.well_data || {})[wname];
            if (wd) {
                const wvars = Object.keys(wd);
                wellVars.value = wvars;
                selectedWellVar.value = wvars.length > 0 ? wvars[0] : '';
                nextTick(() => drawWellPlot());
            }
        });

        function formatValue(v) {
            if (typeof v === 'number') {
                return Number.isInteger(v) ? v : v.toFixed(3);
            }
            return v;
        }

        onMounted(() => {
            loadCaseDefaults(caseType.value);
        });

        return {
            caseType, caseInfo, params, paramErrors,
            simStatus, simMessage, isValid, activeTab,
            simResults, reservoirVars, selectedReservoirVar,
            currentStep, totalSteps, showDelta,
            currentImageSrc, imageLoading,
            wellNames, selectedWell, wellVars, selectedWellVar,
            wellCanvas,
            selectCase, onParamChange, resetDefaults,
            runSimulation, formatValue,
            fetchReservoirImage, drawWellPlot,
            firstStep, lastStep, prevStep, nextStep
        };
    }
}).mount('#app');
</script>
</body>
</html>
"""
end

# ---------------------------------------------------------------------------
# Server start
# ---------------------------------------------------------------------------

function _start_server(; port::Int=8000, host::String="0.0.0.0")
    Genie.config.run_as_server = true
    up(port, host)
end

# Allow running directly: julia app.jl
if abspath(PROGRAM_FILE) == @__FILE__
    _start_server()
end
