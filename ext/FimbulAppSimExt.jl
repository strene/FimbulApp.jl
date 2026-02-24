"""
Extension that provides actual Fimbul.jl simulation support.
Loaded automatically when both Fimbul and JutulDarcy are available.
"""
module FimbulAppSimExt

using Fimbul, Jutul, JutulDarcy, CairoMakie
using FimbulApp.CaseParameters
using FimbulApp.Simulation

import FimbulApp.Simulation: setup_case, run_simulation, convert_well_data, generate_reservoir_images!
import Base64: base64encode

# Unit helpers using JutulDarcy SI units
const _darcy = si_unit(:darcy)
const _atm = si_unit(:atm)

# Unit conversion constants
const _K_to_C = 273.15
const _m3s_to_Ls = 1000.0
const _Pa_to_bar = 1e-5

"""Convert user-facing parameters to Fimbul kwargs and create a simulation case."""
function Simulation.setup_case(case_type::CaseType, params)
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
        error("Case type $case_type is not yet supported in the simulation extension.")
    end
end

"""Convert well output data from SI units to user-friendly units."""
function Simulation.convert_well_data(wdata)
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

"""Generate reservoir state images using Jutul's plot_cell_data and JutulDarcy's plot_well."""
function Simulation.generate_reservoir_images!(result::Simulation.SimulationResult, case, states)
    try
        mesh = physical_representation(reservoir_model(case.model).data_domain)
        vars = [:Temperature]
        for var in vars
            svar = string(var)
            images = String[]
            for (n, state) in enumerate(states)
                println(keys(state))
                fig = Figure(size = (800, 600))
                ax = Axis3(fig[1, 1], title = "Temperature at step $n (°C)", aspect = :data, zreversed=true)
                Jutul.plot_cell_data!(ax, mesh, state[var])
                io = IOBuffer()
                show(io, MIME("image/png"), fig)
                img_data = take!(io)
                base64_img = base64encode(img_data)
                push!(images, "data:image/png;base64,$base64_img")
            end
            result.reservoir_images[svar] = images
        end
        return true
    catch e
        @warn "Could not generate reservoir images (load CairoMakie for visualization): $e"
        return false
    end
end

"""Run a full Fimbul simulation and return structured results."""
function Simulation.run_simulation(case_type::CaseType, params)
    result = Simulation.SimulationResult()
    errors = CaseParameters.validate_params(params)
    if !isempty(errors)
        result.status = Simulation.FAILED
        result.message = join(["$(e[1]): $(e[2])" for e in errors], "; ")
        return result
    end
    try
        result.status = Simulation.RUNNING
        case = setup_case(case_type, params)
        sim_result = simulate_reservoir(case)
        result.status = Simulation.COMPLETED
        result.message = "Simulation completed successfully."
        # Extract well data from results with unit conversion
        ws, states, t = sim_result
        for (wname, wdata) in pairs(ws)
            result.well_data[string(wname)] = convert_well_data(wdata)
        end
        result.timestamps = t
        # Generate reservoir images using plot_cell_data + plot_well
        images_ok = generate_reservoir_images!(result, case, states)
        # Fall back to raw state data if image generation failed
        if !images_ok
            for state in states
                d = Dict{String, Vector{Float64}}()
                for (k, v) in pairs(state)
                    sk = string(k)
                    if v isa AbstractVector{<:Real}
                        d[sk] = Float64.(v)
                    end
                end
                push!(result.reservoir_states, Simulation.ReservoirState(d))
            end
        end
    catch e
        result.status = Simulation.FAILED
        result.message = "Simulation failed: $(sprint(showerror, e))"
    end
    return result
end

end # module
