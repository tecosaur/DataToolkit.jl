function getlayer(::Nothing)
    length(STACK) == 0 && throw(error("The data collection stack is empty"))
    first(STACK)
end

function getlayer(name::AbstractString)
    length(STACK) == 0 && throw(error("The data collection stack is empty"))
    matchinglayers = filter(c -> c.name == name, STACK)
    if length(matchinglayers) == 0
        throw(error("No collections within the stack matched the name '$name'"))
    elseif length(matchinglayers) > 1
        throw(error("Multiple collections within the stack matched the name '$name'"))
    else
        first(matchinglayers)
    end
end

function getlayer(uuid::UUID)
    length(STACK) == 0 && throw(error("The data collection stack is empty"))
    matchinglayers = filter(c -> c.uuid == uuid, STACK)
    if length(matchinglayers) == 0
        throw(error("No collections within the stack matched the name '$name'"))
    else
        first(matchinglayers)
    end
end
