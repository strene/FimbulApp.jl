using Test

# Load the CaseParameters module directly for testing
include(joinpath(@__DIR__, "..", "src", "CaseParameters.jl"))
using .CaseParameters

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

end
