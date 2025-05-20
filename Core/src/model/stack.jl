"""
    getlayer([stack])

Return the first [`DataCollection`](@ref) on the `stack`.

`stack` defaults to [`STACK`](@ref), and must be a `Vector{DataCollection}`.
"""
function getlayer(stack::Vector{DataCollection}, ::Nothing = nothing)
    length(stack) == 0 && throw(EmptyStackError())
    first(stack)
end

getlayer(::Nothing = nothing) = getlayer(STACK, nothing)

"""
    getlayer([stack], name::AbstractString)
    getlayer([stack], uuid::UUID)

Find the [`DataCollection`](@ref) in [`STACK`](@ref) with `name`/`uuid`.

`stack` defaults to [`STACK`](@ref), and must be a `Vector{DataCollection}`.
"""
function getlayer(stack::Vector{DataCollection}, name::AbstractString)
    length(stack) == 0 && throw(EmptyStackError())
    matchinglayers = filter(c -> c.name == name, stack)
    if length(matchinglayers) == 0
        throw(UnresolveableIdentifier{DataCollection}(String(name)))
    elseif length(matchinglayers) > 1
        throw(AmbiguousIdentifier(name, matchinglayers))
    else
        first(matchinglayers)
    end
end

# Documented above
function getlayer(stack::Vector{DataCollection}, uuid::UUID)
    length(stack) == 0 && throw(EmptyStackError())
    matchinglayers = filter(c -> c.uuid == uuid, stack)
    if length(matchinglayers) == 1
        first(matchinglayers)
    elseif length(matchinglayers) == 0
        throw(UnresolveableIdentifier{DataCollection}(uuid))
    else
        throw(AmbiguousIdentifier(uuid, matchinglayers))
    end
end

getlayer(id::Union{<:AbstractString, UUID}) = getlayer(STACK, id)
