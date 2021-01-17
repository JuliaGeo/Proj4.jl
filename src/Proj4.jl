module Proj4

using PROJ_jll
using CEnum
using StaticArrays
using CoordinateTransformations

export Projection, # proj_types.jl
       transform, transform!,  # proj_functions.jl
       is_latlong, is_geocent, compare_datums, spheroid_params,
       xy2lonlat, xy2lonlat!, lonlat2xy, lonlat2xy!

# geodesic support
export geod_direct, geod_inverse, geod_destination, geod_distance

# these are part of the deprecated PROJ API, and will be removed soon
include("projection_codes.jl") # ESRI and EPSG projection strings
include("proj_capi.jl") # low-level C-facing functions (corresponding to src/proj_api.h)
include("proj_geodesic.jl") # low-level C-facing functions (corresponding to src/geodesic.h)

# these are part of the new PROJ API
include("proj_common.jl")
include("coord.jl")
include("proj_c.jl")
include("error.jl")

function _version()
    m = match(r"(\d+).(\d+).(\d+),.+", _get_release())
    VersionNumber(parse(Int, m[1]), parse(Int, m[2]), parse(Int, m[3]))
end

"Parsed version number for the underlying version of libproj"
const version = _version()

# Detect underlying libproj support for geodesic calculations
const has_geodesic_support = true

include("proj_types.jl") # type definitions for proj objects
include("proj_functions.jl") # user-facing proj functions

"Get a global error string in human readable form"
error_message() = _strerrno()

"""
Load a null-terminated list of strings

It takes a `PROJ_STRING_LIST`, which is a `Ptr{Cstring}`, and returns a `Vector{String}`.
"""
function unsafe_loadstringlist(ptr::Ptr{Cstring})
    strings = Vector{String}()
    (ptr == C_NULL) && return strings
    i = 1
    cstring = unsafe_load(ptr, i)
    while cstring != C_NULL
        push!(strings, unsafe_string(cstring))
        i += 1
        cstring = unsafe_load(ptr, i)
    end
    strings
end

const PROJ_LIB = Ref{String}()

"Module initialization function"
function __init__()
    # register custom error handler
    funcptr = @cfunction(log_func, Ptr{Cvoid}, (Ptr{Cvoid}, Cint, Cstring))
    proj_log_func(C_NULL, funcptr)

    # point to the location of the provided shared resources
    PROJ_LIB[] = joinpath(PROJ_jll.artifact_dir, "share", "proj")
    proj_context_set_search_paths(1, [PROJ_LIB[]])
end

end # module
