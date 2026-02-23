"""
    Simulation

Interface for running Fimbul geothermal simulations via the web application.
This module defines the simulation API that bridges the web UI with Fimbul.jl.
The actual Fimbul calls are in the FimbulAppSimExt extension (loaded when
Fimbul and JutulDarcy are available).
"""
module Simulation

using ..CaseParameters

export SimulationStatus, IDLE, RUNNING, COMPLETED, FAILED
export SimulationResult, run_simulation, setup_case

@enum SimulationStatus IDLE RUNNING COMPLETED FAILED

"""Container for simulation results."""
mutable struct SimulationResult
    status::SimulationStatus
    message::String
    well_data::Dict{String, Any}
    timestamps::Vector{Float64}
    SimulationResult() = new(IDLE, "", Dict{String, Any}(), Float64[])
end

"""
    setup_case(case_type, params) -> (case, info)

Set up a Fimbul simulation case from the given parameters.
Returns `nothing` if Fimbul is not available.
"""
function setup_case end

"""
    run_simulation(case_type, params) -> SimulationResult

Run a Fimbul simulation with the given parameters.
Returns a SimulationResult with status and data.
"""
function run_simulation(case_type::CaseType, params)
    result = SimulationResult()
    errors = validate_params(params)
    if !isempty(errors)
        result.status = FAILED
        result.message = join(["$(e[1]): $(e[2])" for e in errors], "; ")
        return result
    end
    result.status = RUNNING
    result.message = "Simulation requires Fimbul.jl and JutulDarcy.jl. " *
        "Install them with: using Pkg; Pkg.add([\"Fimbul\", \"JutulDarcy\"])"
    return result
end

end # module
