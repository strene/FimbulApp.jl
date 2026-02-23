"""
Extension that provides actual Fimbul.jl simulation support.
Loaded automatically when both Fimbul and JutulDarcy are available.
"""
module FimbulAppSimExt

using Fimbul, JutulDarcy
using FimbulApp.CaseParameters
using FimbulApp.Simulation

import FimbulApp.Simulation: setup_case, run_simulation

# Unit helpers using JutulDarcy SI units
const _darcy = JutulDarcy.si_unit(:darcy)
const _atm = JutulDarcy.si_unit(:atm)

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
        # Extract well data from results
        ws = JutulDarcy.full_well_outputs(sim_result.model, sim_result.result)
        for (wname, wdata) in ws
            result.well_data[string(wname)] = wdata
        end
        result.timestamps = cumsum(case.dt)
    catch e
        result.status = Simulation.FAILED
        result.message = "Simulation failed: $(sprint(showerror, e))"
    end
    return result
end

end # module
