export euclidean_distance, manhattan_distance, get_direction, spacesize


"""
    spacesize(model::ABM)

Return the size of the model's space. Works for [`GridSpace`](@ref),
[`GridSpaceSingle`](@ref) and [`ContinuousSpace`](@ref).
"""
spacesize(model::ABM) = spacesize(abmspace(model))

#######################################################################################
# %% Distances and directions in Grid/Continuous space
#######################################################################################
"""
    euclidean_distance(a, b, model::ABM)

Return the euclidean distance between `a` and `b` (either agents or agent positions),
respecting periodic boundary conditions (if in use). Works with any space where it makes
sense: currently `AbstractGridSpace` and `ContinuousSpace`.

Example usage in the [Flocking model](@ref).
"""
euclidean_distance(a::AbstractAgent, b::AbstractAgent, model::ABM) = 
    euclidean_distance(a.pos, b.pos, abmspace(model))
euclidean_distance(p1, p2, model::ABM) = euclidean_distance(p1, p2, abmspace(model))

function euclidean_distance(
    p1::Any,
    p2::Any,
    space::Union{ContinuousSpace{D,false},AbstractGridSpace{D,false}},
) where {D}
    sqrt(sum(abs2.(p1 .- p2)))
end

function euclidean_distance(
    p1::Any,
    p2::Any,
    space::Union{ContinuousSpace{D,true},AbstractGridSpace{D,true}},
) where {D}
    direct = abs.(p1 .- p2)
    sqrt(sum(min.(direct, spacesize(space) .- direct).^2))
end

function euclidean_distance(
    p1::Any,
    p2::Any,
    space::Union{ContinuousSpace{D,P},AbstractGridSpace{D,P}}
) where {D,P}
    s = spacesize(space)
    distance_squared = zero(eltype(p1))
    for i in eachindex(p1)
        if P[i]
            distance_squared += euclidean_distance_periodic(p1[i], p2[i], s[i])^2
        else
            distance_squared += euclidean_distance_direct(p1[i], p2[i])^2
        end
    end
    return sqrt(distance_squared)
end

function euclidean_distance_direct(x1::Real, x2::Real)
    abs(x1 - x2)
end
function euclidean_distance_periodic(x1::Real, x2::Real, l::Real)
    direct = abs(x1 - x2)
    min(direct, l - direct)
end

"""
    manhattan_distance(a, b, model::ABM)

Return the manhattan distance between `a` and `b` (either agents or agent positions),
respecting periodic boundary conditions (if in use). Works with any space where it makes
sense: currently `AbstractGridSpace` and `ContinuousSpace`.
"""
manhattan_distance(a::AbstractAgent, b::AbstractAgent, model::ABM) = 
    manhattan_distance(a.pos, b.pos, abmspace(model))
manhattan_distance(p1, p2, model::ABM) = manhattan_distance(p1, p2, abmspace(model))

function manhattan_distance(
    p1::Any,
    p2::Any,
    space::Union{ContinuousSpace{D,false},AbstractGridSpace{D,false}},
) where {D}
    sum(manhattan_distance_direct.(p1, p2))
end

function manhattan_distance(
    p1::Any,
    p2::Any,
    space::Union{ContinuousSpace{D,true},AbstractGridSpace{D,true}}
) where {D}
    sum(manhattan_distance_periodic.(p1, p2, spacesize(space)))
end

function manhattan_distance(
    p1::Any,
    p2::Any,
    space::Union{ContinuousSpace{D,P},AbstractGridSpace{D,P}}
) where {D,P}
    s = spacesize(space)
    distance = zero(eltype(p1))
    for i in eachindex(p1)
        if P[i]
            distance += manhattan_distance_periodic(p1[i], p2[i], s[i])
        else
            distance += manhattan_distance_direct(p1[i], p2[i])
        end
    end
    return distance
end

function manhattan_distance_direct(x1::Real, x2::Real)
    abs(x1 - x2)
end
function manhattan_distance_periodic(x1::Real, x2::Real, s::Real)
    direct = abs(x1 - x2)
    min(direct, s - direct)
end

"""
    get_direction(from, to, model::ABM)
Return the direction vector from the position `from` to position `to` taking into account
periodicity of the space.
"""
get_direction(from, to, model::ABM) = get_direction(from, to, abmspace(model))

function get_direction(
    from::Any,
    to::Any,
    space::Union{ContinuousSpace{D,true},AbstractGridSpace{D,true}},
) where {D}
    direct_dir = to .- from
    inverse_dir = direct_dir .- sign.(direct_dir) .* spacesize(space)
    return map((x, y) -> abs(x) <= abs(y) ? x : y, direct_dir, inverse_dir)
end

function get_direction(
    from::Any,
    to::Any,
    space::Union{AbstractGridSpace{D,false},ContinuousSpace{D,false}},
) where {D}
    return to .- from
end

function get_direction(
    from::Any,
    to::Any,
    space::Union{ContinuousSpace{D,P},AbstractGridSpace{D,P}}
) where {D,P}
    direct_dir = to .- from
    inverse_dir = direct_dir .- sign.(direct_dir) .* spacesize(space)
    return map(
        i -> P[i] ?
        (abs(direct_dir[i]) <= abs(inverse_dir[i]) ? direct_dir[i] : inverse_dir[i]) :
        direct_dir[i],
        1:D
    )
end

#######################################################################################
# %% Utilities for graph-based spaces (Graph/OpenStreetMap)
#######################################################################################
GraphBasedSpace = Union{GraphSpace,OpenStreetMapSpace}
_get_graph(space::GraphSpace) = space.graph
_get_graph(space::OpenStreetMapSpace) = space.map.graph
"""
    nv(model::ABM)
Return the number of positions (vertices) in the `model` space.
"""
Graphs.nv(model::ABM{<:GraphBasedSpace}) = Graphs.nv(_get_graph(abmspace(model)))

"""
    ne(model::ABM)
Return the number of edges in the `model` space.
"""
Graphs.ne(model::ABM{<:GraphBasedSpace}) = Graphs.ne(_get_graph(abmspace(model)))

positions(model::ABM{<:GraphBasedSpace}) = 1:nv(model)

function nearby_positions(
    position::Integer,
    model::ABM{<:GraphBasedSpace},
    radius::Integer;
    kwargs...,
)
    nearby = copy(nearby_positions(position, model; kwargs...))
    radius == 1 && return nearby
    seen = Set{Int}(nearby)
    push!(seen, position)
    k, n = 0, nv(model)
    for _ in 2:radius
        thislevel = @view nearby[k+1:end]
        isempty(thislevel) && return nearby
        k = length(nearby)
        k == n && return nearby
    	for v in thislevel
    	    for w in nearby_positions(v, model; kwargs...)
    	        if w ∉ seen
    	            push!(seen, w)
    	            push!(nearby, w)
    	        end
    	    end
    	end
    end
    return nearby
end


