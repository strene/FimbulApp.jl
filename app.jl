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
    ))
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

    <!-- Main Content -->
    <main class="main-content">
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

                <!-- Results Visualization Placeholder -->
                <div class="viz-section" v-if="simStatus === 'COMPLETED'">
                    <h4>Results</h4>
                    <div id="results-chart" class="chart-container">
                        <canvas id="chart"></canvas>
                    </div>
                </div>
            </section>
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

<script src="https://unpkg.com/vue@3/dist/vue.global.prod.js"></script>
<script>
const { createApp, ref, reactive, computed, watch, onMounted } = Vue;

createApp({
    setup() {
        const caseType = ref('DOUBLET');
        const caseInfo = ref(null);
        const params = reactive({});
        const paramErrors = reactive({});
        const simStatus = ref('IDLE');
        const simMessage = ref('');
        const isValid = ref(true);

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
            } catch (e) {
                simStatus.value = 'FAILED';
                simMessage.value = 'Request failed: ' + e.message;
            }
        }

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
            simStatus, simMessage, isValid,
            selectCase, onParamChange, resetDefaults,
            runSimulation, formatValue
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
