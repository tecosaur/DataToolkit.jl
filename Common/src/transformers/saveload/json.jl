function load(::DataLoader{:json}, from::IO, as::Type)
    @import JSON3
    JSON3.read(from)
end

supportedtypes(::Type{DataLoader{:json}}) =
    [QualifiedType(Any)]

function save(writer::DataWriter{:json}, dest::IO, info)
    @import JSON3
    if get(writer, "pretty", false)
        JSON3.pretty(dest, info)
    else
        JSON3.write(dest, info)
    end
end

createpriority(::Type{DataLoader{:json}}) = 10

create(::Type{DataLoader{:json}}, source::String) =
    !isnothing(match(r"\.json$"i, source))
