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

- [Julia](https://julialang.org/) ≥ 1.10

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

### Running Simulations

To actually run geothermal simulations (not just configure them), install Fimbul.jl
and JutulDarcy.jl:

```julia
using Pkg
Pkg.add("Fimbul")
Pkg.add("JutulDarcy")
```

When these packages are loaded, the simulation backend is automatically activated
via Julia's extension mechanism.

## Features

- **Intuitive parameter setup** – Configure key simulation properties using sliders
  and text input fields
- **Real-time validation** – Parameter values are validated as you adjust them
- **Five case types** – All standard geothermal energy applications supported by Fimbul
- **Responsive design** – Works on desktop and tablet screens
- **API-first** – JSON REST API for programmatic access

## Architecture

Built with [Genie.jl](https://genieframework.com/) and a Vue.js frontend:

```
FimbulApp.jl/
├── src/
│   ├── FimbulApp.jl          # Main module
│   ├── CaseParameters.jl     # Parameter definitions and validation
│   └── Simulation.jl         # Simulation interface
├── ext/
│   └── FimbulAppSimExt.jl    # Fimbul.jl integration (loaded on demand)
├── app.jl                    # Web server and routes
├── public/css/style.css      # Dashboard styles
└── test/runtests.jl          # Tests
```

## API Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/` | Dashboard UI |
| GET | `/api/defaults/:case_type` | Default parameters for a case type |
| POST | `/api/validate` | Validate parameter values |
| POST | `/api/simulate` | Run a simulation |

## License

MIT
