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
export SimulationResult, run_simulation, setup_case, ReservoirState
export convert_well_data, generate_reservoir_images!, render_reservoir_image

@enum SimulationStatus IDLE RUNNING COMPLETED FAILED

"""Container for a single reservoir report step."""
struct ReservoirState
    data::Dict{String, Vector{Float64}}
end

"""Container for simulation results."""
mutable struct SimulationResult
    status::SimulationStatus
    message::String
    well_data::Dict{String, Any}
    timestamps::Vector{Float64}
    reservoir_states::Vector{ReservoirState}
    reservoir_images::Dict{String, Vector{String}}
    reservoir_vars::Vector{String}
    num_steps::Int
    SimulationResult() = new(IDLE, "", Dict{String, Any}(), Float64[], ReservoirState[], Dict{String, Vector{String}}(), String[], 0)
end

"""
    setup_case(case_type, params) -> (case, info)

Set up a Fimbul simulation case from the given parameters.
Returns `nothing` if Fimbul is not available.
"""
function setup_case end

"""
    convert_well_data(wdata) -> Dict{String, Any}

Convert well output data from SI units to user-friendly units.
Default implementation returns data as-is (extension provides conversion).
"""
function convert_well_data(wdata)
    converted = Dict{String, Any}()
    for (key, vals) in pairs(wdata)
        converted[string(key)] = vals
    end
    return converted
end

"""
    generate_reservoir_images!(result, case, states)

Generate pre-rendered reservoir state images using Jutul's plot_cell_data
and JutulDarcy's plot_well. Requires a Makie backend (e.g. CairoMakie).
Default implementation is a no-op (extension provides rendering).
"""
function generate_reservoir_images!(result::SimulationResult, case, states)
    # No-op: the FimbulAppSimExt extension provides the actual rendering
    return false
end

"""
    render_reservoir_image(var, step) -> String

Render a single reservoir state image on demand for the given variable name
and 1-based step index. Returns a base64-encoded PNG string, or empty string
if rendering is not available. Results are cached server-side.
Default implementation returns empty string (extension provides rendering).
"""
function render_reservoir_image(var::AbstractString, step::Int)
    return ""
end

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
