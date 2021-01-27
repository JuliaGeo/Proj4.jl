using Test
using StaticArrays
using Proj4
import PROJ_jll

function read_cmd(cmd)
    bytes = read(cmd)
    str = String(bytes)
    # on Windows there are CFLR line endings
    lf_only = replace(str, "\r" => "")
    no_tabs = replace(lf_only, "\t" => " ")
    return String(strip(no_tabs))
end

# https://proj.org/apps/cs2cs.html#using-epsg-crs-codes
@test PROJ_jll.cs2cs() do cs2cs
    read_cmd(pipeline(IOBuffer("45N 2E"), `$cs2cs EPSG:4326 EPSG:32631`))
end == "421184.70 4983436.77 0.00"

# https://proj.org/usage/transformation.html?#grid-based-datum-adjustments
@test PROJ_jll.cs2cs() do cs2cs
    withenv("PROJ_NETWORK" => "ON") do
        # instead of ntv1_can.dat we can also specify ca_nrc_ntv1_can.tif
        read_cmd(pipeline(IOBuffer("-111 50"),
        `$cs2cs +proj=latlong +ellps=clrk66 +nadgrids=ntv1_can.dat
            +to +proj=latlong +ellps=GRS80 +datum=NAD83`))
    end
end == "111d0'3.006\"W 50d0'0.125\"N 0.000"

@test PROJ_jll.cs2cs() do cs2cs
    withenv("PROJ_NETWORK" => "ON") do
        read_cmd(pipeline(IOBuffer("-111 50"),
        `$cs2cs +proj=latlong +ellps=clrk66 +nadgrids=ca_nrc_ntv1_can.tif
            +to +proj=latlong +ellps=GRS80 +datum=NAD83`))
    end
end == "111d0'3.006\"W 50d0'0.125\"N 0.000"


function xyzt_transform_cli(point::AbstractVector; network::Bool=false)
    # convert the vector to a string like "-33 151 5 2020"
    input = String(strip(string(point'), ('[', ']')))
    xyzt_transform_cli(input; network)
end

function xyzt_transform_cli(point::String; network::Bool=false)
    proj_network = network ? "ON" : nothing
    PROJ_jll.cs2cs() do cs2cs
        withenv("PROJ_NETWORK" => proj_network) do
            read_cmd(pipeline(IOBuffer(point),
                `$cs2cs -d 6 EPSG:4326+5773 EPSG:7856+5711`))
        end
    end
end

function xyzt_transform(point::AbstractVector; network::Bool=false)
    proj_network = network ? "ON" : nothing
    tr = Proj4.Transformation("EPSG:4326+5773", "EPSG:7856+5711", normalize = true)
    tr(point)
end

# http://osgeo-org.1560.x6.nabble.com/PROJ-Different-results-from-cs2cs-vs-C-API-code-td5446396.html

# When you use cs2cs and do not specify it (as the 4th value in the coordinate),
# the time is sent to HUGE_VAL, which makes it not being used at all
# (so here as the reference epoch for the time-dependent Helmert transformation is 2020.0,
# it will be as if you specified 2020.0).

xy1 = "313152.777216 6346936.495714"
xy2 = "313152.777214 6346936.495810"
@test xyzt_transform_cli(SA[-33, 151, 5, 2020]; network=true) == "$xy1 5.280678 2020"
@test xyzt_transform_cli("-33 151 5 2020"; network=true) == "$xy1 5.280678 2020"
# no z correction with no network, as expected
@test xyzt_transform_cli(SA[-33, 151, 5, 2020]; network=false) == "$xy2 5.000000 2020"
# year 0, different xyz, as expected
@test xyzt_transform_cli(SA[-33, 151, 5, 0]; network=true) == "313188.897461 6347047.288591 4.940935 0"
# no time input is like passing 2020, as expected
@test xyzt_transform_cli(SA[-33, 151, 5]; network=true) == "$xy1 5.280678"

# need to switch axis order here
# interestingly this does not respond to the PROJ_NETWORK environment variable,
# but does respond to enabling it in the context
Proj4.proj_context_is_network_enabled()
@test Proj4.proj_context_set_enable_network(1) == 1
# this is like passing floatmax() to the cli, but if we do it correctly we expect
# it to be like the version that passes only xyz to the cli
@test xyzt_transform(SA_F64[151, -33, 5]) == SA[313152.7772137531, 6.346936495809965e6, 5.280647277836724]
# this is expected, like the above
@test xyzt_transform(SA_F64[151, -33, 5, 2020]) == SA[313152.77721557155, 6.34693649571435e6, 5.28067830334755, 2020.0]

@test xyzt_transform(SA_F64[151, -33, 5, floatmax() * 2]) == SA[313152.77721557155, 6.34693649571435e6, 5.28067830334755, Inf]

@test PROJ_jll.cs2cs() do cs2cs
    read_cmd(pipeline(IOBuffer("-33 151 5 0"), `$cs2cs -d 8 EPSG:4326+5773 EPSG:7856+5711`))
end == "313152.77721375 6346936.49580996 5.00000000 0"

@test PROJ_jll.projinfo() do projinfo
    read_cmd(`$projinfo  -o PROJ EPSG:25832`)
end == """PROJ.4 string:
+proj=utm +zone=32 +ellps=GRS80 +towgs84=0,0,0,0,0,0,0 +units=m +no_defs +type=crs
"""

PROJ_jll.projinfo() do projinfo
    n_candidate_ops = "Candidate operations found: 4"
    grid_not_found = "Grid us_nga_egm96_15.tif needed but not found on the system." *
        " Can be obtained at https://cdn.proj.org/us_nga_egm96_15.tif"
    info = read_cmd(`$projinfo -s EPSG:4326+5773 -t EPSG:7856+5711`)
    @test occursin(n_candidate_ops, info)
    @test occursin(grid_not_found, info)
end
