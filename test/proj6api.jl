using Test
using StaticArrays
using Proj4
import PROJ_jll

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
    for i = 1:n
        operation = Proj4.proj_list_get(results, i - 1)
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
    pj = Proj4.proj_destroy(pj)
    pj = Proj4.proj_destroy(pj)
    # Julia crashes if proj_destroy is called twice on the same non nullptr,
    # since the contents at that address are already wiped. To prevent this,
    # change the input binding directly after, e.g. pj = proj_destroy(pj)  # -> C_NULL
end

@testset "inverse transformation" begin
    tr = Proj4.Transformation("EPSG:4326", "+proj=utm +zone=32 +datum=WGS84")
    tr⁻¹ = inv(tr)
    tr¹ = inv(tr⁻¹)

    # inverse twice should get the same transform back
    wkt_type = Proj4.PJ_WKT2_2019
    @test Proj4.proj_as_wkt(tr⁻¹.pj, wkt_type) != Proj4.proj_as_wkt(tr.pj, wkt_type)
    @test Proj4.proj_as_wkt(tr¹.pj, wkt_type) == Proj4.proj_as_wkt(tr.pj, wkt_type)
end

@testset "single transformation" begin
    source_crs = Proj4.proj_create("EPSG:4326")
    target_crs = Proj4.proj_create("EPSG:28992")
    @test source_crs isa Ptr{Nothing}
    @test target_crs isa Ptr{Nothing}
    tr = Proj4.Transformation(source_crs, target_crs)

    a = Proj4.proj_coord(52.16, 5.39)
    b = Proj4.proj_trans(tr.pj, Proj4.PJ_FWD, a)
    @test a != b
    @test b ≈ Proj4.proj_coord(155191.3538124342, 463537.1362732911)

    # with normalize=True, we need to use lon/lat, and still get x/y out
    tr = Proj4.Transformation(source_crs, target_crs, normalize = true)
    a = Proj4.proj_coord(5.39, 52.16)
    b = Proj4.proj_trans(tr.pj, Proj4.PJ_FWD, a)
    @test a != b
    @test b ≈ Proj4.proj_coord(155191.3538124342, 463537.1362732911)
end

@testset "dense 4D coord vector transformation" begin
    source_crs = Proj4.proj_create("EPSG:4326")
    target_crs = Proj4.proj_create("EPSG:28992")
    tr = Proj4.Transformation(source_crs, target_crs, normalize = true)
    # This array is mutated in place. Note that this array needs to have 4D elements,
    # with 2D elements it will only do every other one
    A = [Proj4.proj_coord(5.39, 52.16) for _ = 1:5]
    err = Proj4.proj_trans_array(tr.pj, Proj4.PJ_FWD, length(A), A)
    @test err == 0
    B = [Proj4.proj_coord(155191.3538124342, 463537.1362732911) for _ = 1:5]
    @test A ≈ B

    # since A is not in target_crs, we will get an error on a second call
    err = Proj4.proj_trans_array(tr.pj, Proj4.PJ_FWD, length(A), A)
    errno = Proj4.proj_errno(tr.pj)
    @test err == errno == -14
    @test Proj4.proj_errno_string(errno) == "latitude or longitude exceeded limits"
    # reset error
    Proj4.proj_errno_reset(tr.pj)
    @test Proj4.proj_errno(tr.pj) == 0
    # test triggering finalizer manually
    finalize(tr)
    @test tr.pj === C_NULL
end

@testset "generic array transformation" begin
    source_crs = Proj4.proj_create("EPSG:4326")
    target_crs = Proj4.proj_create("EPSG:28992")
    tr = Proj4.Transformation(source_crs, target_crs, normalize = true)

    # inplace transformation of vector of 2D coordinates
    # using https://proj.org/development/reference/functions.html#c.proj_trans_generic
    A = [SA[5.39, 52.16] for _ = 1:5]
    st = sizeof(first(A))
    ptr = pointer(A)
    n = length(A)
    # 8 is sizeof(Float64), so ptr + 8 points to first latitude element
    n_done = Proj4.proj_trans_generic(
        tr.pj,
        Proj4.PJ_FWD,
        ptr,
        st,
        n,
        ptr + 8,
        st,
        n,
        C_NULL,
        C_NULL,
        C_NULL,
        C_NULL,
        C_NULL,
        C_NULL,
    )
    @test n_done == n
    B = [SA[155191.3538124342, 463537.1362732911] for _ = 1:5]
    @test A ≈ B
end

tr = Proj4.Transformation("EPSG:4326", "EPSG:28992", normalize = true)
tr(Proj4.proj_coord(5.39, 52.16))
b = tr(SA[5.39, 52.16, 0.0, 0.0])
@test b isa SVector{4, Float64}
b = tr(SA[5.39, 52.16])
@test b isa SVector{2, Float64}
tr(SA_F32[5.39, 52.16])
@test b isa SVector{2, Float64}
b = tr(SA[5, 52])
@test b isa SVector{2, Float64}
