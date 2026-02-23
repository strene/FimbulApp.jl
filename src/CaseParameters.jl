"""
    CaseParameters

Parameter definitions and defaults for all Fimbul geothermal case types.
Each case type has a struct with documented defaults matching the Fimbul.jl API.
"""
module CaseParameters

export CaseType, DOUBLET, EGS, AGS, ATES, BTES
export DoubletParams, EGSParams, AGSParams, ATESParams, BTESParams
export default_params, param_metadata, validate_params

"""Supported geothermal case types."""
@enum CaseType DOUBLET EGS AGS ATES BTES

const CASE_LABELS = Dict(
    DOUBLET => "Geothermal Doublet",
    EGS     => "Enhanced Geothermal System (EGS)",
    AGS     => "Advanced Geothermal System (AGS)",
    ATES    => "Aquifer Thermal Energy Storage (ATES)",
    BTES    => "Borehole Thermal Energy Storage (BTES)",
)

const CASE_DESCRIPTIONS = Dict(
    DOUBLET => "A conventional geothermal doublet with an injection well and a production well in a layered reservoir.",
    EGS     => "Enhanced geothermal system with stimulated fractures connecting injection and production wells in hot dry rock.",
    AGS     => "Advanced (closed-loop) geothermal system with a U-tube or coaxial heat exchanger in a deep borehole.",
    ATES    => "Aquifer thermal energy storage using hot and cold wells for seasonal heat storage in a permeable aquifer.",
    BTES    => "Borehole thermal energy storage using an array of closely-spaced boreholes for seasonal heat storage.",
)

const CASE_CATEGORIES = Dict(
    DOUBLET => :production,
    EGS     => :production,
    AGS     => :production,
    ATES    => :storage,
    BTES    => :storage,
)

# --- Parameter structs ---

"""Parameters for a geothermal doublet simulation."""
Base.@kwdef mutable struct DoubletParams
    spacing_top::Float64 = 100.0
    spacing_bottom::Float64 = 1000.0
    depth_1::Float64 = 800.0
    depth_2::Float64 = 2500.0
    temperature_inj::Float64 = 20.0
    rate::Float64 = 300.0
    temperature_surface::Float64 = 10.0
    num_years::Int = 100
end

"""Parameters for an enhanced geothermal system (EGS) simulation."""
Base.@kwdef mutable struct EGSParams
    fracture_radius::Float64 = 250.0
    fracture_spacing::Float64 = 100.0
    fracture_aperture::Float64 = 0.5
    well_distance::Float64 = 600.0
    lateral_length::Float64 = 1000.0
    well_depth::Float64 = 4000.0
    porosity::Float64 = 0.01
    permeability::Float64 = 0.1
    rock_thermal_conductivity::Float64 = 2.5
    rock_heat_capacity::Float64 = 900.0
    temperature_inj::Float64 = 25.0
    rate::Float64 = 100.0
    num_years::Int = 20
end

"""Parameters for an advanced geothermal system (AGS) simulation."""
Base.@kwdef mutable struct AGSParams
    porosity::Float64 = 0.01
    permeability::Float64 = 1.0
    rock_thermal_conductivity::Float64 = 2.5
    rock_heat_capacity::Float64 = 900.0
    temperature_surface::Float64 = 10.0
    thermal_gradient::Float64 = 0.03
    rate::Float64 = 25.0
    temperature_inj::Float64 = 25.0
    num_years::Int = 50
end

"""Parameters for an aquifer thermal energy storage (ATES) simulation."""
Base.@kwdef mutable struct ATESParams
    well_distance::Float64 = 500.0
    aquifer_thickness::Float64 = 100.0
    depth::Float64 = 1000.0
    porosity::Float64 = 0.35
    permeability::Float64 = 1000.0
    rock_thermal_conductivity::Float64 = 2.0
    rock_heat_capacity::Float64 = 900.0
    temperature_charge::Float64 = 95.0
    temperature_discharge::Float64 = 25.0
    rate_charge::Float64 = 50.0
    temperature_surface::Float64 = 10.0
    thermal_gradient::Float64 = 0.03
    num_years::Int = 10
end

"""Parameters for a borehole thermal energy storage (BTES) simulation."""
Base.@kwdef mutable struct BTESParams
    num_wells::Int = 48
    num_sectors::Int = 6
    well_spacing::Float64 = 5.0
    well_depth::Float64 = 50.0
    temperature_charge::Float64 = 90.0
    temperature_discharge::Float64 = 10.0
    rate_charge::Float64 = 0.5
    temperature_surface::Float64 = 10.0
    geothermal_gradient::Float64 = 0.03
    num_years::Int = 4
end

"""Metadata for each parameter: (label, unit, min, max, step, tooltip)."""
const PARAM_METADATA = Dict(
    # Doublet
    :spacing_top => (label="Surface well spacing", unit="m", min=10.0, max=500.0, step=10.0,
        tooltip="Horizontal distance between wells at the surface"),
    :spacing_bottom => (label="Reservoir well spacing", unit="m", min=100.0, max=5000.0, step=50.0,
        tooltip="Horizontal distance between wells in the reservoir"),
    :depth_1 => (label="Deviation depth", unit="m", min=100.0, max=5000.0, step=50.0,
        tooltip="Depth at which the well starts to deviate"),
    :depth_2 => (label="Well depth", unit="m", min=500.0, max=8000.0, step=50.0,
        tooltip="Total depth of the wells"),
    :temperature_inj => (label="Injection temperature", unit="°C", min=5.0, max=100.0, step=1.0,
        tooltip="Temperature of injected water"),
    :rate => (label="Flow rate", unit="m³/h", min=10.0, max=1000.0, step=10.0,
        tooltip="Injection and production rate"),
    :temperature_surface => (label="Surface temperature", unit="°C", min=-10.0, max=40.0, step=1.0,
        tooltip="Temperature at the surface"),
    :num_years => (label="Simulation years", unit="yr", min=1, max=500, step=1,
        tooltip="Number of years to simulate"),
    # EGS
    :fracture_radius => (label="Fracture radius", unit="m", min=50.0, max=1000.0, step=10.0,
        tooltip="Radius of EGS fractures"),
    :fracture_spacing => (label="Fracture spacing", unit="m", min=10.0, max=500.0, step=5.0,
        tooltip="Distance between fractures along the well lateral"),
    :fracture_aperture => (label="Fracture aperture", unit="mm", min=0.1, max=5.0, step=0.1,
        tooltip="Hydraulic aperture of fractures"),
    :well_distance => (label="Well distance", unit="m", min=50.0, max=5000.0, step=50.0,
        tooltip="Distance between injection and production wells"),
    :lateral_length => (label="Lateral length", unit="m", min=100.0, max=5000.0, step=50.0,
        tooltip="Length of horizontal well section"),
    :well_depth => (label="Well depth", unit="m", min=500.0, max=8000.0, step=50.0,
        tooltip="Depth of the wells"),
    # AGS / shared
    :porosity => (label="Porosity", unit="-", min=0.001, max=0.5, step=0.01,
        tooltip="Rock porosity (fraction)"),
    :permeability => (label="Permeability", unit="mD", min=0.001, max=5000.0, step=1.0,
        tooltip="Rock permeability in millidarcys"),
    :rock_thermal_conductivity => (label="Thermal conductivity", unit="W/(m·K)", min=0.5, max=10.0, step=0.1,
        tooltip="Rock thermal conductivity"),
    :rock_heat_capacity => (label="Rock heat capacity", unit="J/(kg·K)", min=100.0, max=2000.0, step=50.0,
        tooltip="Specific heat capacity of rock"),
    :thermal_gradient => (label="Geothermal gradient", unit="K/m", min=0.01, max=0.10, step=0.005,
        tooltip="Rate of temperature increase with depth"),
    # ATES
    :aquifer_thickness => (label="Aquifer thickness", unit="m", min=10.0, max=500.0, step=5.0,
        tooltip="Thickness of the aquifer layer"),
    :depth => (label="Aquifer depth", unit="m", min=100.0, max=5000.0, step=50.0,
        tooltip="Depth to the top of the aquifer"),
    :temperature_charge => (label="Charge temperature", unit="°C", min=30.0, max=150.0, step=1.0,
        tooltip="Temperature of injected water during charging"),
    :temperature_discharge => (label="Discharge temperature", unit="°C", min=5.0, max=50.0, step=1.0,
        tooltip="Temperature of injected water during discharging"),
    :rate_charge => (label="Charge rate", unit="m³/h", min=1.0, max=500.0, step=1.0,
        tooltip="Injection/production rate during charging"),
    # BTES
    :num_wells => (label="Number of wells", unit="-", min=4, max=200, step=1,
        tooltip="Total number of boreholes in the BTES system"),
    :num_sectors => (label="Number of sectors", unit="-", min=1, max=20, step=1,
        tooltip="Number of sectors the wells are divided into"),
    :well_spacing => (label="Well spacing", unit="m", min=2.0, max=20.0, step=0.5,
        tooltip="Horizontal distance between adjacent boreholes"),
    :geothermal_gradient => (label="Geothermal gradient", unit="K/m", min=0.01, max=0.10, step=0.005,
        tooltip="Rate of temperature increase with depth"),
)

"""Return the default parameter struct for a given case type."""
function default_params(case_type::CaseType)
    case_type == DOUBLET && return DoubletParams()
    case_type == EGS     && return EGSParams()
    case_type == AGS     && return AGSParams()
    case_type == ATES    && return ATESParams()
    case_type == BTES    && return BTESParams()
    error("Unknown case type: $case_type")
end

"""Get metadata for a parameter field."""
function param_metadata(field::Symbol)
    return get(PARAM_METADATA, field, nothing)
end

"""Return parameter field names for a given case type."""
function param_fields(case_type::CaseType)
    case_type == DOUBLET && return fieldnames(DoubletParams)
    case_type == EGS     && return fieldnames(EGSParams)
    case_type == AGS     && return fieldnames(AGSParams)
    case_type == ATES    && return fieldnames(ATESParams)
    case_type == BTES    && return fieldnames(BTESParams)
    error("Unknown case type: $case_type")
end

"""Validate parameters and return a list of (field, message) errors."""
function validate_params(params::DoubletParams)
    errors = Tuple{Symbol,String}[]
    params.spacing_top <= 0 && push!(errors, (:spacing_top, "Must be positive"))
    params.spacing_bottom <= 0 && push!(errors, (:spacing_bottom, "Must be positive"))
    params.depth_1 <= 0 && push!(errors, (:depth_1, "Must be positive"))
    params.depth_2 <= params.depth_1 && push!(errors, (:depth_2, "Must be greater than deviation depth"))
    params.rate <= 0 && push!(errors, (:rate, "Must be positive"))
    params.num_years < 1 && push!(errors, (:num_years, "Must be at least 1"))
    return errors
end

function validate_params(params::EGSParams)
    errors = Tuple{Symbol,String}[]
    params.fracture_radius <= 0 && push!(errors, (:fracture_radius, "Must be positive"))
    params.fracture_spacing <= 0 && push!(errors, (:fracture_spacing, "Must be positive"))
    params.fracture_aperture <= 0 && push!(errors, (:fracture_aperture, "Must be positive"))
    params.well_distance <= 0 && push!(errors, (:well_distance, "Must be positive"))
    params.porosity <= 0 || params.porosity > 1 && push!(errors, (:porosity, "Must be between 0 and 1"))
    params.rate <= 0 && push!(errors, (:rate, "Must be positive"))
    params.num_years < 1 && push!(errors, (:num_years, "Must be at least 1"))
    return errors
end

function validate_params(params::AGSParams)
    errors = Tuple{Symbol,String}[]
    params.porosity <= 0 || params.porosity > 1 && push!(errors, (:porosity, "Must be between 0 and 1"))
    params.permeability <= 0 && push!(errors, (:permeability, "Must be positive"))
    params.rate <= 0 && push!(errors, (:rate, "Must be positive"))
    params.thermal_gradient <= 0 && push!(errors, (:thermal_gradient, "Must be positive"))
    params.num_years < 1 && push!(errors, (:num_years, "Must be at least 1"))
    return errors
end

function validate_params(params::ATESParams)
    errors = Tuple{Symbol,String}[]
    params.well_distance <= 0 && push!(errors, (:well_distance, "Must be positive"))
    params.aquifer_thickness <= 0 && push!(errors, (:aquifer_thickness, "Must be positive"))
    params.depth <= 0 && push!(errors, (:depth, "Must be positive"))
    params.porosity <= 0 || params.porosity > 1 && push!(errors, (:porosity, "Must be between 0 and 1"))
    params.rate_charge <= 0 && push!(errors, (:rate_charge, "Must be positive"))
    params.temperature_charge <= params.temperature_discharge &&
        push!(errors, (:temperature_charge, "Must be greater than discharge temperature"))
    params.num_years < 1 && push!(errors, (:num_years, "Must be at least 1"))
    return errors
end

function validate_params(params::BTESParams)
    errors = Tuple{Symbol,String}[]
    params.num_wells < 4 && push!(errors, (:num_wells, "Must be at least 4"))
    params.num_sectors < 1 && push!(errors, (:num_sectors, "Must be at least 1"))
    params.num_sectors > params.num_wells && push!(errors, (:num_sectors, "Cannot exceed number of wells"))
    params.well_spacing <= 0 && push!(errors, (:well_spacing, "Must be positive"))
    params.rate_charge <= 0 && push!(errors, (:rate_charge, "Must be positive"))
    params.temperature_charge <= params.temperature_discharge &&
        push!(errors, (:temperature_charge, "Must be greater than discharge temperature"))
    params.num_years < 1 && push!(errors, (:num_years, "Must be at least 1"))
    return errors
end

"""Convert a parameter struct to a Dict{Symbol, Any}."""
function params_to_dict(params)
    Dict(f => getfield(params, f) for f in fieldnames(typeof(params)))
end

"""Create a parameter struct from a Dict{String, Any} (e.g., from JSON)."""
function dict_to_params(case_type::CaseType, d::AbstractDict)
    T = case_type == DOUBLET ? DoubletParams :
        case_type == EGS     ? EGSParams :
        case_type == AGS     ? AGSParams :
        case_type == ATES    ? ATESParams :
        case_type == BTES    ? BTESParams :
        error("Unknown case type: $case_type")
    kwargs = Dict{Symbol, Any}()
    for f in fieldnames(T)
        key = string(f)
        if haskey(d, key)
            ft = fieldtype(T, f)
            kwargs[f] = convert(ft, d[key])
        end
    end
    return T(; kwargs...)
end

end # module
