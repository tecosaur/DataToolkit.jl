function getlayer(::Nothing)
    length(STACK) == 0 && throw(EmptyStackError())
    first(STACK)
end

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

function getlayer(uuid::UUID)
    length(STACK) == 0 && throw(EmptyStackError())
    matchinglayers = filter(c -> c.uuid == uuid, STACK)
    if length(matchinglayers) == 0
        throw(AmbiguousIdentifier(uuid, matchinglayers))
    else
        first(matchinglayers)
    end
end
