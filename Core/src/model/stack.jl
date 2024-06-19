"""
    getlayer(::Nothing)

Return the first `DataCollection` on the `STACK`.
"""
function getlayer(::Nothing)
    length(STACK) == 0 && throw(EmptyStackError())
    first(STACK)
end

"""
    getlayer(name::AbstractString)
    getlayer(uuid::UUID)

Find the `DataCollection` in `STACK` with `name`/`uuid`.
"""
function getlayer(name::AbstractString)
    length(STACK) == 0 && throw(EmptyStackError())
    matchinglayers = filter(c -> c.name == name, STACK)
    if length(matchinglayers) == 0
        throw(UnresolveableIdentifier{DataCollection}(String(name)))
    elseif length(matchinglayers) > 1
        throw(AmbiguousIdentifier(name, matchinglayers))
    else
        first(matchinglayers)
    end
end

# Documented above
function getlayer(uuid::UUID)
    length(STACK) == 0 && throw(EmptyStackError())
    matchinglayers = filter(c -> c.uuid == uuid, STACK)
    if length(matchinglayers) == 1
        first(matchinglayers)
    elseif length(matchinglayers) == 0
        throw(UnresolveableIdentifier{DataCollection}(uuid))
    else
        throw(AmbiguousIdentifier(uuid, matchinglayers))
    end
end
