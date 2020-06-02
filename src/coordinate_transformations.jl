mutable struct CRS2CRS <: CoordinateTransformations.Transformation
    rep::Ptr{Cvoid}
    direction::PJ_DIRECTION
end

function CRS2CRS(source::Projection, dest::Projection, direction::PJ_DIRECTION = PJ_FWD; area = C_NULL, normalize = true)

    if direction == PJ_IDENT || proj_is_equivalent_to(source.rep, dest.rep, PJ_COMP_EQUIVALENT) == 1
        return IdentityTransformation()
    end

    pj_init = ccall(
        (:proj_create_crs_to_crs_from_pj, PROJ_jll.libproj),
        Ptr{Cvoid},
        (Ptr{Cvoid}, Ptr{Cvoid}, Ptr{Cvoid}, Ptr{Cchar}),
        source.rep,  dest.rep,   area,       C_NULL
    )

    obj = if normalize
        pj_normalized = proj_normalize_for_visualization(pj_init)
        proj_destroy(pj_init)
        CRS2CRS(pj_normalized, direction)
    else
        CRS2CRS(pj_normalized, direction)
    end

    finalizer(obj) do
        proj_destroy(obj.rep)
    end

    return obj
end


function CRS2CRS(source::String, dest::String, direction::PJ_DIRECTION = PJ_FWD; area = C_NULL, normalize = true)

    if direction == PJ_IDENT || source == direction
        return IdentityTransformation()
    end

    pj_init = proj_create_crs_to_crs(source, dest, area)

    obj = if normalize
        pj_normalized = proj_normalize_for_visualization(pj_init)
        proj_destroy(pj_init)
        CRS2CRS(pj_normalized, direction)
    else
        CRS2CRS(pj_normalized, direction)
    end

    finalizer(obj) do
        proj_destroy(obj.rep)
    end

    return obj
end

Base.inv(cs::CRS2CRS) = CRS2CRS(cs.rep, inv(cs.direction))

function Base.inv(dir::PJ_DIRECTION)
    return if dir == PJ_IDENT
        PJ_IDENT
    elseif dir == PJ_FWD
        PJ_INV
    else
        PJ_FWD
    end
end

function CoordinateTransformations.transform_deriv(cs::CRS2CRS, x)
    coord = proj_coord(x...)
    factors = proj_factors(cs.rep, coord)
    return [dx_dlam dx_dphi; dy_dlam dy_dphi]
end

function (transformation::CRS2CRS)(x::T) where T
    coord = if length(x) == 2
        proj_coord(x..., 0, 0)
    elseif length(x) == 3
        proj_coord(x..., 0)
    elseif length(x) == 4
        proj_coord(x...)
    else
        error("Input must have length 2, 3 or 4! Found $(length(x)).")
    end

    xyzt = proj_trans(transformation.rep, transformation.direction, coord).xyzt

    return if length(x) == 2
        T(xyzt.x, xyzt.y)
    elseif length(x) == 3
        T(xyzt.x, xyzt.y, xyzt.z)
    elseif length(x) == 4
        proj_coord(xyzt.x, xyzt.y, xyzt.z, xyzt.t)
    else
        error("Input must have length 2, 3 or 4! Found $(length(x)).")
    end
end



function proj_trans_generic(P, direction, x::Vector{Float64}, y::Vector{Float64}, z::Vector{Float64} = zeros(length(x)), t::Vector{Float64} = zeros(length(x)))
    return proj_trans_generic(
        P, direction,
        x, sizeof(Float64), length(x),
        y, sizeof(Float64), length(y),
        z, sizeof(Float64), length(z),
        t, sizeof(Float64), length(t),
    )
end
