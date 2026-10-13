# FimbulApp.jl

Web application for setting up, visualizing, simulating and analysing geothermal
energy applications using [Fimbul.jl](https://github.com/sintefmath/Fimbul.jl).

## Supported Applications

**Energy Production:**
- **Geothermal Doublet** – Injection and production well pair in a layered reservoir
- **Enhanced Geothermal System (EGS)** – Stimulated fractures connecting wells in hot dry rock
- **Advanced Geothermal System (AGS)** – Closed-loop heat exchanger in a deep borehole

**Energy Storage:**
- **Aquifer Thermal Energy Storage (ATES)** – Seasonal heat storage using hot/cold wells in a permeable aquifer
- **Borehole Thermal Energy Storage (BTES)** – Seasonal heat storage using an array of closely-spaced boreholes

## Getting Started

### Prerequisites

- [Julia](https://julialang.org/) ≥ 1.11

FimbulApp is pinned to **Fimbul.jl v0.3.5**. The simulation backend (Fimbul,
Jutul, JutulDarcy and CairoMakie) is a regular dependency and is installed
automatically.

### Installation

```julia
using Pkg
Pkg.add(url="https://github.com/strene/FimbulApp.jl")
```

### Running the Application

```julia
using FimbulApp
FimbulApp.start()
```

Then open [http://localhost:8000](http://localhost:8000) in your browser.

To use a different port:

```julia
FimbulApp.start(port=9000)
```

Simulations run in a background task while the web server keeps answering
progress requests. This works best with an interactive thread, which Julia
≥ 1.12 starts by default. On Julia 1.11, start Julia with `julia -t 1,1`.

## Features

- **Intuitive parameter setup** – Configure key simulation properties using sliders
  and text input fields
- **Real-time validation** – Parameter values are validated as you adjust them
- **Five case types** – Doublet, EGS, AGS, ATES and BTES, set up with the corresponding Fimbul case functions
- **Interactive results** – Step through 3D reservoir states (absolute or difference from
  the initial state) alongside well output curves
- **Export and compare** – Download well output as CSV and overlay cached runs for comparison
- **Live progress** – Simulations run in the background with a progress bar, runtime and ETA
- **Console** – Read-only view of the simulation output (Fimbul setup messages and Jutul's
  progress/timing report), as it would appear in the Julia REPL
- **Responsive design** – Works on desktop and tablet screens
- **API-first** – JSON REST API for programmatic access

## Architecture

Built with [Genie.jl](https://genieframework.com/) and a Vue.js frontend:

```
FimbulApp.jl/
├── src/
│   ├── FimbulApp.jl          # Main module
│   ├── CaseParameters.jl     # Parameter definitions and validation
│   ├── Console.jl            # Output capture and terminal emulation for the console tab
│   └── Simulation.jl         # Fimbul case setup, simulation and image rendering
├── app.jl                    # Web server, routes and dashboard
├── public/css/style.css      # Dashboard styles
├── public/js/                # Vue.js (bundled)
└── test/runtests.jl          # Tests
```

## API Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/` | Dashboard UI |
| GET | `/api/defaults/:case_type` | Default parameters for a case type |
| POST | `/api/validate` | Validate parameter values |
| POST | `/api/simulate` | Start a simulation in the background |
| GET | `/api/simulation/status?since=` | Progress, runtime, ETA and console output (console lines only if changed since version `since`) |
| GET | `/api/simulation/result` | Results of the most recent simulation |
| GET | `/api/reservoir_image/:var/:step?delta=` | Rendered reservoir state (base64 PNG) |

## Known Issues

- **AGS** fails during mesh generation in Fimbul v0.3.5 (`Cannot overwrite face neighbor
  for cell ...`). This is a Fimbul bug that also affects `Fimbul.ags()` with default
  arguments; the app reports the error instead of crashing.

## License

MIT
