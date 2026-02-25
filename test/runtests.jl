using Test

# Load the CaseParameters module directly for testing
include(joinpath(@__DIR__, "..", "src", "CaseParameters.jl"))
using .CaseParameters

# Try to load Simulation module (requires Fimbul, Jutul, JutulDarcy, CairoMakie)
const HAS_SIM_DEPS = try
    include(joinpath(@__DIR__, "..", "src", "Simulation.jl"))
    true
catch e
    if isa(e, ArgumentError) || (isa(e, LoadError) && isa(e.error, ArgumentError))
        @warn "Skipping Simulation tests: required packages not available" exception=e
    else
        rethrow(e)
    end
    false
end

if HAS_SIM_DEPS
    using .Simulation
end

@testset "FimbulApp" begin

    @testset "CaseType enum" begin
        @test DOUBLET isa CaseType
        @test EGS isa CaseType
        @test AGS isa CaseType
        @test ATES isa CaseType
        @test BTES isa CaseType
    end

    @testset "Default parameters" begin
        @testset "DoubletParams defaults" begin
            p = default_params(DOUBLET)
            @test p isa DoubletParams
            @test p.spacing_top == 100.0
            @test p.spacing_bottom == 1000.0
            @test p.depth_1 == 800.0
            @test p.temperature_inj == 20.0
            @test p.rate == 300.0
            @test p.num_years == 100
        end

        @testset "EGSParams defaults" begin
            p = default_params(EGS)
            @test p isa EGSParams
            @test p.fracture_radius == 250.0
            @test p.fracture_spacing == 100.0
            @test p.fracture_aperture == 0.5
            @test p.porosity == 0.01
            @test p.num_years == 20
        end

        @testset "AGSParams defaults" begin
            p = default_params(AGS)
            @test p isa AGSParams
            @test p.porosity == 0.01
            @test p.thermal_gradient == 0.03
            @test p.rate == 25.0
            @test p.num_years == 50
        end

        @testset "ATESParams defaults" begin
            p = default_params(ATES)
            @test p isa ATESParams
            @test p.well_distance == 500.0
            @test p.aquifer_thickness == 100.0
            @test p.temperature_charge == 95.0
            @test p.temperature_discharge == 25.0
            @test p.num_years == 10
        end

        @testset "BTESParams defaults" begin
            p = default_params(BTES)
            @test p isa BTESParams
            @test p.num_wells == 48
            @test p.num_sectors == 6
            @test p.well_spacing == 5.0
            @test p.temperature_charge == 90.0
            @test p.num_years == 4
        end
    end

    @testset "Parameter validation" begin
        @testset "DoubletParams validation" begin
            p = DoubletParams()
            @test isempty(validate_params(p))

            p.spacing_top = -10.0
            errs = validate_params(p)
            @test any(e -> e[1] == :spacing_top, errs)

            p = DoubletParams(num_years=0)
            errs = validate_params(p)
            @test any(e -> e[1] == :num_years, errs)

            p = DoubletParams(depth_2=100.0, depth_1=800.0)
            errs = validate_params(p)
            @test any(e -> e[1] == :depth_2, errs)
        end

        @testset "ATESParams validation" begin
            p = ATESParams()
            @test isempty(validate_params(p))

            p = ATESParams(temperature_charge=10.0, temperature_discharge=25.0)
            errs = validate_params(p)
            @test any(e -> e[1] == :temperature_charge, errs)

            p = ATESParams(well_distance=-100.0)
            errs = validate_params(p)
            @test any(e -> e[1] == :well_distance, errs)
        end

        @testset "BTESParams validation" begin
            p = BTESParams()
            @test isempty(validate_params(p))

            p = BTESParams(num_wells=2)
            errs = validate_params(p)
            @test any(e -> e[1] == :num_wells, errs)

            p = BTESParams(num_sectors=100)
            errs = validate_params(p)
            @test any(e -> e[1] == :num_sectors, errs)

            p = BTESParams(temperature_charge=5.0, temperature_discharge=10.0)
            errs = validate_params(p)
            @test any(e -> e[1] == :temperature_charge, errs)
        end

        @testset "EGSParams validation" begin
            p = EGSParams()
            @test isempty(validate_params(p))

            p = EGSParams(fracture_radius=-10.0)
            errs = validate_params(p)
            @test any(e -> e[1] == :fracture_radius, errs)
        end

        @testset "AGSParams validation" begin
            p = AGSParams()
            @test isempty(validate_params(p))

            p = AGSParams(thermal_gradient=-0.01)
            errs = validate_params(p)
            @test any(e -> e[1] == :thermal_gradient, errs)
        end
    end

    @testset "Parameter metadata" begin
        m = param_metadata(:spacing_top)
        @test !isnothing(m)
        @test m.label == "Surface well spacing"
        @test m.unit == "m"
        @test m.min < m.max

        m = param_metadata(:num_wells)
        @test !isnothing(m)
        @test m.label == "Number of wells"

        @test isnothing(param_metadata(:nonexistent_field))
    end

    @testset "params_to_dict and dict_to_params" begin
        p = DoubletParams(spacing_top=200.0, num_years=50)
        d = CaseParameters.params_to_dict(p)
        @test d[:spacing_top] == 200.0
        @test d[:num_years] == 50

        d2 = Dict{String,Any}("spacing_top" => 300.0, "num_years" => 75)
        p2 = CaseParameters.dict_to_params(DOUBLET, d2)
        @test p2.spacing_top == 300.0
        @test p2.num_years == 75
        # Fields not in dict should get defaults
        @test p2.rate == 300.0
    end

    @testset "Case labels and descriptions" begin
        for ct in [DOUBLET, EGS, AGS, ATES, BTES]
            @test haskey(CaseParameters.CASE_LABELS, ct)
            @test haskey(CaseParameters.CASE_DESCRIPTIONS, ct)
            @test haskey(CaseParameters.CASE_CATEGORIES, ct)
            @test !isempty(CaseParameters.CASE_LABELS[ct])
            @test !isempty(CaseParameters.CASE_DESCRIPTIONS[ct])
        end
    end

    @testset "Case categories" begin
        @test CaseParameters.CASE_CATEGORIES[DOUBLET] == :production
        @test CaseParameters.CASE_CATEGORIES[EGS] == :production
        @test CaseParameters.CASE_CATEGORIES[AGS] == :production
        @test CaseParameters.CASE_CATEGORIES[ATES] == :storage
        @test CaseParameters.CASE_CATEGORIES[BTES] == :storage
    end

    @testset "CSV export utilities" begin
        @testset "generate_csv_filename" begin
            p = DoubletParams()
            fname = generate_csv_filename(DOUBLET, p)
            @test endswith(fname, ".csv")
            @test startswith(fname, "DOUBLET_")
            @test occursin("spacing_top=100.0", fname)
            @test occursin("num_years=100", fname)
            @test occursin("rate=300.0", fname)

            p2 = EGSParams(fracture_radius=300.0)
            fname2 = generate_csv_filename(EGS, p2)
            @test startswith(fname2, "EGS_")
            @test occursin("fracture_radius=300.0", fname2)
        end

        @testset "well_data_to_csv" begin
            timestamps = [0.0, 1.0, 2.0]
            well_data = Dict(
                "Well1" => Dict("Temperature [°C]" => [50.0, 48.0, 46.0],
                                "Pressure [bar]" => [100.0, 99.0, 98.0]),
                "Well2" => Dict("Temperature [°C]" => [30.0, 31.0, 32.0])
            )
            csv = well_data_to_csv(well_data, timestamps)
            lines = split(strip(csv), "\n")
            @test length(lines) == 4  # header + 3 data rows
            header = lines[1]
            @test occursin("Time [days]", header)
            @test occursin("Well1: Temperature [°C]", header)
            @test occursin("Well1: Pressure [bar]", header)
            @test occursin("Well2: Temperature [°C]", header)
            # Check data rows have correct number of columns
            ncols = length(split(header, ","))
            for i in 2:4
                @test length(split(lines[i], ",")) == ncols
            end
            # Check first data row contains timestamp
            @test startswith(lines[2], "0.0,")
        end

        @testset "well_data_to_csv empty" begin
            csv = well_data_to_csv(Dict{String,Any}(), Float64[])
            lines = split(strip(csv), "\n")
            @test length(lines) == 1  # header only
            @test occursin("Time [days]", lines[1])
        end
    end

    if HAS_SIM_DEPS
        @testset "SimulationResult" begin
            @testset "Default construction" begin
                r = SimulationResult()
                @test r.status == IDLE
                @test r.message == ""
                @test isempty(r.well_data)
                @test isempty(r.timestamps)
                @test isempty(r.reservoir_states)
                @test isempty(r.reservoir_images)
                @test isempty(r.reservoir_vars)
                @test r.num_steps == 0
            end

            @testset "ReservoirState" begin
                d = Dict{String, Vector{Float64}}("Temperature" => [300.0, 310.0, 320.0])
                s = ReservoirState(d)
                @test s.data["Temperature"] == [300.0, 310.0, 320.0]
            end

            @testset "reservoir_states population" begin
                r = SimulationResult()
                push!(r.reservoir_states, ReservoirState(Dict("T" => [1.0, 2.0], "P" => [100.0, 200.0])))
                push!(r.reservoir_states, ReservoirState(Dict("T" => [1.5, 2.5], "P" => [110.0, 210.0])))
                @test length(r.reservoir_states) == 2
                @test r.reservoir_states[1].data["T"] == [1.0, 2.0]
                @test r.reservoir_states[2].data["P"] == [110.0, 210.0]
            end

            @testset "reservoir_images field" begin
                r = SimulationResult()
                r.reservoir_images["Temperature"] = ["base64img1", "base64img2"]
                @test length(r.reservoir_images["Temperature"]) == 2
                @test r.reservoir_images["Temperature"][1] == "base64img1"
            end

            @testset "reservoir_vars and num_steps" begin
                r = SimulationResult()
                push!(r.reservoir_vars, "Temperature")
                push!(r.reservoir_vars, "Pressure")
                r.num_steps = 10
                @test r.reservoir_vars == ["Temperature", "Pressure"]
                @test r.num_steps == 10
            end

            @testset "run_simulation with invalid params" begin
                p = DoubletParams(spacing_top=-10.0)
                result = run_simulation(DOUBLET, p)
                @test result.status == FAILED
                @test occursin("spacing_top", result.message)
            end

            @testset "convert_well_data" begin
                # Temperature: K → °C
                wdata = Dict(:Temperature => [350.0, 340.0])
                converted = convert_well_data(wdata)
                @test haskey(converted, "Temperature [°C]")
                @test converted["Temperature [°C]"] ≈ [76.85, 66.85]

                # Pressure: Pa → bar
                wdata = Dict(:Pressure => [1e6, 2e6])
                converted = convert_well_data(wdata)
                @test haskey(converted, "Pressure [bar]")
                @test converted["Pressure [bar]"] ≈ [10.0, 20.0]

                # Rate: m³/s → L/s
                wdata = Dict(:rate => [0.01, 0.02])
                converted = convert_well_data(wdata)
                @test haskey(converted, "rate [L/s]")
                @test converted["rate [L/s]"] ≈ [10.0, 20.0]
            end

            @testset "generate_reservoir_images!" begin
                r = SimulationResult()
                result = generate_reservoir_images!(r, nothing, [])
                @test result == false
                @test isempty(r.reservoir_images)
            end

            @testset "render_reservoir_image without simulation" begin
                # Without a simulation run, returns empty string
                img = render_reservoir_image("Temperature", 1)
                @test img == ""
                # SubString should also work
                s = SubString("Temperature", 1)
                img2 = render_reservoir_image(s, 1)
                @test img2 == ""
                # Delta mode should also return empty string
                img3 = render_reservoir_image("Temperature", 1; delta=true)
                @test img3 == ""
            end
        end
    end

end
