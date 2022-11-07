function load(::DataLoader{:json}, from::IO, as::Type)
    @use JSON3
    JSON3.read(from)
end

supportedtypes(::Type{DataLoader{:json}}) =
    [QualifiedType(Any)]

function save(writer::DataWriter{:json}, dest::IO, info)
    @use JSON3
    if get(writer, "pretty", false)
        JSON3.pretty(dest, info)
    else
        JSON3.write(dest, info)
    end
end
