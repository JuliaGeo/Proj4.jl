using Test
using StaticArrays
import Proj4

@testset "Error handling" begin
    @test Proj4.proj_errno_string(0) == nothing
    @test Proj4.proj_errno_string(1) == "Operation not permitted"
    @test Proj4.proj_errno_string(2) == "No such file or directory"

    # this throws an internal error that is handled by our log_func
    @test_throws Proj4.PROJError Proj4.proj_create("+proj=bobbyjoe")
    # ensure we have reset the error state
    @test Proj4.proj_context_errno() == 0

end

@testset "Database" begin
    crs = Proj4.proj_create_from_database("EPSG", "4326", Proj4.PJ_CATEGORY_CRS, false)
    Proj4.proj_errno(crs)
    Proj4.proj_get_id_code(crs, 0)
end

@testset "Create" begin
    pj_latlon = Proj4.proj_create("EPSG:4326")

    esriwkt = """GEOGCS["GCS_WGS_1984",DATUM["D_WGS_1984",SPHEROID["WGS_1984",6378137.0,298.257223563]],PRIMEM["Greenwich",0.0],UNIT["Degree",0.0174532925199433]]"""
    pj2 = Proj4.proj_create(esriwkt)

    @test startswith(Proj4.proj_as_wkt(pj2, Proj4.PJ_WKT1_ESRI, C_NULL), "GEOGCS")
    @test startswith(Proj4.proj_as_wkt(pj2, Proj4.PJ_WKT2_2018, C_NULL), "GEOGCRS")
end

@testset "Transformation between CRS" begin
    # taken from http://osgeo-org.1560.x6.nabble.com/PROJ-PROJ-6-0-0-proj-create-operation-factory-context-behavior-td5403470.html
    src = Proj4.proj_create("IGNF:REUN47GAUSSL")   # area : 55.17,-21.42,55.92,-20.76
    tgt = Proj4.proj_create("IGNF:RGAF09UTM20")    # area : -63.2,14.25,-60.73,18.2
    factory = Proj4.proj_create_operation_factory_context(C_NULL)
    @test factory != C_NULL
    @test Proj4.proj_context_errno() == 0
    results = Proj4.proj_create_operations(src, tgt, factory)
    @test results != C_NULL
    n = Proj4.proj_list_get_count(results)
    for i in 1:n
        operation = Proj4.proj_list_get(results, i-1)
        hasballpark = Bool(Proj4.proj_coordoperation_has_ballpark_transformation(operation))
        print("""Operation $i
            Name: $(Proj4.proj_get_name(operation))
            Has Ballpark: $hasballpark
        """)
        info = Proj4.proj_pj_info(operation)
        print("""Info $i:
            ID:$(unsafe_string(info.id))
            Desc:$(unsafe_string(info.description))
            Def:$(unsafe_string(info.definition))
            Inv:$(Bool(info.has_inverse))
            Acc:$(info.accuracy)
        """)
        Proj4.proj_destroy(operation)
    end
    Proj4.proj_list_destroy(results)

    Proj4.proj_operation_factory_context_destroy(factory)
    Proj4.proj_destroy(src)
    Proj4.proj_destroy(tgt)
end

@testset "Quickstart" begin
    # https://proj.org/development/quickstart.html

    pj = Proj4.proj_create_crs_to_crs(
        "EPSG:4326",  # source
        "+proj=utm +zone=32 +datum=WGS84",  # target, also EPSG:32632
    )

    # This will ensure that the order of coordinates for the input CRS
    # will be longitude, latitude, whereas EPSG:4326 mandates latitude,
    # longitude
    pj_for_gis = Proj4.proj_normalize_for_visualization(pj)
    Proj4.proj_destroy(pj)
    pj = pj_for_gis

    # a coordinate union representing Copenhagen: 55d N, 12d E
    # Given that we have used proj_normalize_for_visualization(), the order of
    # coordinates is longitude, latitude, and values are expressed in degrees.
    a = Proj4.proj_coord(12, 55)
    @test a isa AbstractVector
    @test a isa SVector{4,Float64}
    @test a isa Proj4.Coord
    @test eltype(a) == Float64
    @test length(a) == 4
    @test sum(a) == 12 + 55
    @test isbits(a)
    @test a[1] === 12.0
    @test a[2] === 55.0
    @test a[3] === 0.0
    @test a[4] === 0.0

    # transform to UTM zone 32
    b = Proj4.proj_trans(pj, Proj4.PJ_FWD, a)
    @test b[1] ≈ 691875.632
    @test b[2] ≈ 6098907.825
    @test b[3] === 0.0
    @test b[4] === 0.0

    # inverse transform, back to geographical
    b = Proj4.proj_trans(pj, Proj4.PJ_INV, b)
    @test b[1] ≈ 12.0
    @test b[2] ≈ 55.0
    @test b[3] === 0.0
    @test b[4] === 0.0

    # Clean up
    Proj4.proj_destroy(pj)
    # TODO julia crashes if proj_destroy is called twice, i.e. on a null pointer
end
