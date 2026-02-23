"""
    FimbulApp

Web application for setting up, visualizing, simulating and analysing
geothermal energy applications using the Fimbul.jl simulation toolbox.

Supports five geothermal case types:

**Energy Production:**
- `DOUBLET` – Geothermal doublet (injection + production well)
- `EGS` – Enhanced Geothermal System (stimulated fractures)
- `AGS` – Advanced Geothermal System (closed-loop heat exchanger)

**Energy Storage:**
- `ATES` – Aquifer Thermal Energy Storage
- `BTES` – Borehole Thermal Energy Storage

## Quick Start

```julia
using FimbulApp
FimbulApp.start()
```

Then open http://localhost:8000 in a browser.
"""
module FimbulApp

include("CaseParameters.jl")
include("Simulation.jl")

using .CaseParameters
using .Simulation

export start

# Re-export key types
export CaseType, DOUBLET, EGS, AGS, ATES, BTES
export DoubletParams, EGSParams, AGSParams, ATESParams, BTESParams

"""
    start(; port=8000, host="0.0.0.0")

Start the FimbulApp web server. Open http://localhost:<port> in a browser.
"""
function start(; port::Int=8000, host::String="0.0.0.0")
    include(joinpath(@__DIR__, "..", "app.jl"))
    _start_server(; port=port, host=host)
end

end # module
