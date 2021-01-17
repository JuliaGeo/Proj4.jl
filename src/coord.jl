const Coord = SVector{4, Float64}

mutable struct Transformation <: CoordinateTransformations.Transformation
    pj::Ptr{PJ}
    function Transformation(pj::Ptr{PJ})
        tr = new(pj)
        finalizer(tr) do tr
            tr.pj = proj_destroy(tr.pj)
        end
        return tr
    end
end

function Transformation(
    source_crs::AbstractString,
    target_crs::AbstractString;
    area::Ptr{PJ_AREA} = C_NULL,
    ctx::Ptr{PJ_CONTEXT} = C_NULL,
    normalize::Bool = false,
)
    pj = proj_create_crs_to_crs(source_crs, target_crs)
    pj = normalize ? normalize_axis_order!(pj, ctx) : pj
    return Transformation(pj)
end

function Transformation(
    source_crs::Ptr{PJ},
    target_crs::Ptr{PJ};
    area::Ptr{PJ_AREA} = C_NULL,
    ctx::Ptr{PJ_CONTEXT} = C_NULL,
    normalize::Bool = false,
)
    pj = proj_create_crs_to_crs_from_pj(source_crs, target_crs)
    pj = normalize ? normalize_axis_order!(pj, ctx) : pj
    return Transformation(pj)
end

"""
    normalize_axis_order!(pj::Ptr{PJ}, ctx = C_NULL)

Call proj_normalize_for_visualization on an object, and return the new object after freeing
the input object.
"""
function normalize_axis_order!(pj::Ptr{PJ}, ctx = C_NULL)
    pj_for_gis = proj_normalize_for_visualization(pj, ctx)
    proj_destroy(pj)
    return pj_for_gis
end

function Base.inv(tr::Transformation, ctx = C_NULL)
    pj_inv = proj_coordoperation_create_inverse(tr.pj, ctx)
    return Transformation(pj_inv)
end
