const TOMLValue = TOML.Internals.Printer.TOMLValue
# TOML_TYPES = Base.uniontypes(TOMLValue)

function getstorage(storage::DataStorage{:raw}, T::Type{<:TOMLValue})
    get(storage, "value", nothing)::Union{T, Nothing}
end

function putstorage(storage::DataStorage{:raw}, ::Type{<:TOMLValue})
    storage
end

supportedtypes(::Type{DataStorage{:raw}}, spec::SmallDict{String, Any}) =
    [QualifiedType(typeof(get(spec, "value", nothing)))]

# NOTE This is hacky, but it's a special case
function save(::DataWriter{:passthrough}, dest::DataStorage{:raw}, info::Any)
    dest.parameters["value"] = info
    write(dest)
    true
end

createpriority(::Type{<:DataStorage{:raw}}) = 90

function create(::Type{<:DataStorage{:raw}}, source::String)
    value = try
        TOML.parse(string("value = ", source))["value"]
    catch end
    if !isnothing(value)
        ["value" => value]
    end
end
