"""
    Simulation

Interface for running Fimbul geothermal simulations via the web application.
This module provides the simulation API that bridges the web UI with Fimbul.jl.
"""
module Simulation

using ..CaseParameters
using Fimbul, Jutul, JutulDarcy, CairoMakie
import Base64: base64encode

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

# Unit helpers using JutulDarcy SI units
const _darcy = si_unit(:darcy)
const _atm = si_unit(:atm)

# Unit conversion constants
const _K_to_C = 273.15
const _m3s_to_Ls = 1000.0
const _Pa_to_bar = 1e-5

# Server-side state for lazy image rendering
const _sim_case = Ref{Any}(nothing)
const _sim_states = Ref{Any}(nothing)
const _sim_state0 = Ref{Any}(nothing)
const _image_cache = Dict{String, String}()
const _colorrange_cache = Dict{String, Tuple{Float64, Float64}}()

"""
    setup_case(case_type, params) -> (case, info)

Convert user-facing parameters to Fimbul kwargs and create a simulation case.
"""
function setup_case(case_type::CaseType, params)
    if case_type == DOUBLET
        return Fimbul.geothermal_doublet(;
            spacing_top      = params.spacing_top,
            spacing_bottom   = params.spacing_bottom,
            depth_1          = params.depth_1,
            depth_2          = params.depth_2,
            temperature_inj  = convert_to_si(params.temperature_inj, :Celsius),
            rate             = params.rate * si_unit(:meter)^3 / si_unit(:hour),
            temperature_surface = convert_to_si(params.temperature_surface, :Celsius),
            num_years        = params.num_years,
        )
    elseif case_type == AGS
        return Fimbul.ags(;
            porosity                 = params.porosity,
            permeability             = params.permeability * 1e-3 * _darcy,
            rock_thermal_conductivity = params.rock_thermal_conductivity * si_unit(:watt) / (si_unit(:meter) * si_unit(:Kelvin)),
            rock_heat_capacity       = params.rock_heat_capacity * si_unit(:joule) / (si_unit(:kilogram) * si_unit(:Kelvin)),
            temperature_surface      = convert_to_si(params.temperature_surface, :Celsius),
            thermal_gradient         = params.thermal_gradient * si_unit(:Kelvin) / si_unit(:meter),
            rate                     = params.rate * si_unit(:meter)^3 / si_unit(:hour),
            temperature_inj          = convert_to_si(params.temperature_inj, :Celsius),
            num_years                = params.num_years,
        )
    elseif case_type == ATES
        return Fimbul.ates(;
            well_distance            = params.well_distance,
            temperature_charge       = convert_to_si(params.temperature_charge, :Celsius),
            temperature_discharge    = convert_to_si(params.temperature_discharge, :Celsius),
            rate_charge              = params.rate_charge * si_unit(:meter)^3 / si_unit(:hour),
            temperature_surface      = convert_to_si(params.temperature_surface, :Celsius),
            thermal_gradient         = params.thermal_gradient * si_unit(:Kelvin) / si_unit(:meter),
        )
    elseif case_type == BTES
        return Fimbul.btes(;
            num_wells            = params.num_wells,
            num_sectors          = params.num_sectors,
            well_spacing         = params.well_spacing,
            temperature_charge   = convert_to_si(params.temperature_charge, :Celsius),
            temperature_discharge = convert_to_si(params.temperature_discharge, :Celsius),
            rate_charge          = params.rate_charge * si_unit(:litre) / si_unit(:second),
            temperature_surface  = convert_to_si(params.temperature_surface, :Celsius),
            geothermal_gradient  = params.geothermal_gradient * si_unit(:Kelvin) / si_unit(:meter),
            num_years            = params.num_years,
        )
    else
        error("Case type $case_type is not yet supported.")
    end
end

"""
    convert_well_data(wdata) -> Dict{String, Any}

Convert well output data from SI units to user-friendly units.
"""
function convert_well_data(wdata)
    converted = Dict{String, Any}()
    for (key, vals) in pairs(wdata)
        skey = string(key)
        if vals isa AbstractVector{<:Real}
            ckey, cvals = _convert_well_variable(skey, vals)
            converted[ckey] = cvals
        else
            converted[skey] = vals
        end
    end
    return converted
end

function _convert_well_variable(name::String, values)
    ln = lowercase(name)
    if occursin("temperature", ln)
        return name * " [°C]", Float64.(values) .- _K_to_C
    elseif occursin("rate", ln) && !occursin("mass", ln)
        return name * " [L/s]", Float64.(values) .* _m3s_to_Ls
    elseif occursin("pressure", ln) || ln == "bhp"
        return name * " [bar]", Float64.(values) .* _Pa_to_bar
    else
        return name, Float64.(values)
    end
end

"""
    _convert_reservoir_variable(var, values; delta=false) -> (converted_values, unit_label)

Convert reservoir state values from SI units to user-friendly units.
Temperature: K → °C, Pressure: Pa → bar.
"""
function _convert_reservoir_variable(var::AbstractString, values; delta::Bool=false)
    ln = lowercase(var)
    if occursin("temperature", ln)
        if delta
            return values, "°C"  # K delta = °C delta
        else
            return values .- _K_to_C, "°C"
        end
    elseif occursin("pressure", ln)
        return values .* _Pa_to_bar, "bar"
    else
        return values, ""
    end
end

"""
    generate_reservoir_images!(result, case, states)

Generate pre-rendered reservoir state images using Jutul's plot_cell_data.
"""
function generate_reservoir_images!(result::SimulationResult, case, states)
    return false
end

"""Compute the global color range for a variable across all timesteps."""
function _get_colorrange(var::AbstractString, delta::Bool)
    cache_key = "$var:$delta"
    haskey(_colorrange_cache, cache_key) && return _colorrange_cache[cache_key]

    states = _sim_states[]
    state0 = _sim_state0[]
    isnothing(states) && return (0.0, 1.0)

    sym = Symbol(var)
    global_min = Inf
    global_max = -Inf
    for i in 1:length(states)
        s = if delta && !isnothing(state0)
            JutulDarcy.delta_state(state0, states[i])
        else
            states[i]
        end
        vals, _ = _convert_reservoir_variable(var, s[sym]; delta=delta)
        lo, hi = extrema(vals)
        global_min = min(global_min, lo)
        global_max = max(global_max, hi)
    end

    result = (global_min, global_max)
    _colorrange_cache[cache_key] = result
    return result
end

"""
    render_reservoir_image(var, step) -> String

Render a single reservoir state image on demand with server-side caching.
Returns a base64-encoded PNG string, or empty string if not available.
"""
function render_reservoir_image(var::AbstractString, step::Int; delta::Bool=false)
    cache_key = "$var:$step:$delta"
    haskey(_image_cache, cache_key) && return _image_cache[cache_key]

    case = _sim_case[]
    states = _sim_states[]
    (isnothing(case) || isnothing(states)) && return ""
    (step < 1 || step > length(states)) && return ""

    try
        mesh = physical_representation(reservoir_model(case.model).data_domain)
        state = states[step]
        title = "$var at step $step"
        if delta
            state0 = _sim_state0[]
            isnothing(state0) && return ""
            state = JutulDarcy.delta_state(state0, state)
            title = "Δ $var at step $step"
        end
        plot_vals, unit_label = _convert_reservoir_variable(var, state[Symbol(var)]; delta=delta)
        if !isempty(unit_label)
            title *= " [$unit_label]"
        end
        cmin, cmax = _get_colorrange(var, delta)
        fig = Figure(size = (800, 600))
        ax = Axis3(fig[1, 1], title = title, aspect = :data, zreversed = true)
        p = Jutul.plot_cell_data!(ax, mesh, plot_vals, outer=true,
            colormap=:seaborn_icefire_gradient, colorrange=(cmin, cmax))
        Colorbar(fig[1, 2], p)
        io = IOBuffer()
        show(io, MIME("image/png"), fig)
        img = base64encode(take!(io))
        _image_cache[cache_key] = img
        return img
    catch e
        @warn "Failed to render reservoir image for $var step $step (delta=$delta): $e"
        return ""
    end
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
    try
        result.status = RUNNING
        case = setup_case(case_type, params)
        sim_result = simulate_reservoir(case[1:5])
        result.status = COMPLETED
        result.message = "Simulation completed successfully."
        # Extract well data from results with unit conversion
        ws, states, t = sim_result
        for (wname, wdata) in pairs(ws)
            result.well_data[string(wname)] = convert_well_data(wdata)
        end
        result.timestamps = t
        # Store case and states for lazy image rendering
        _sim_case[] = case
        _sim_states[] = states
        _sim_state0[] = haskey(case.state0, :Reservoir) ? case.state0[:Reservoir] : nothing
        empty!(_image_cache)
        empty!(_colorrange_cache)
        # Populate reservoir variable names and step count
        result.num_steps = length(states)
        if !isempty(states)
            for (k, v) in pairs(states[1])
                if v isa AbstractVector{<:Real}
                    push!(result.reservoir_vars, string(k))
                end
            end
        end
    catch e
        result.status = FAILED
        result.message = "Simulation failed: $(sprint(showerror, e))"
    end
    return result
end

end # module
