const TOMLValue = TOML.Internals.Printer.TOMLValue
# TOML_TYPES = Base.uniontypes(TOMLValue)

function getstorage(storage::DataStorage{:raw}, T::Type{<:TOMLValue})
    if T <: Dict
        val = @getparam storage."value"::Union{SmallDict, Nothing} nothing
        if !isnothing(val)
            convert(Dict, val)::T
        end
    else
        @getparam storage."value"::Union{T, Nothing} nothing
    end
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

const RAW_DOC = md"""
Access (read/write) values encoded in the data TOML file.

The `passthrough` loader is often useful when using this storage driver.

# Parameters

- `value`: The value in question

# Usage examples

```toml
[[lifemeaning.storage]]
driver = "raw"
value = 42
```

```toml
[[parameters.storage]]
driver = "raw"
value = { a = 3, b = "*", c = false }
```
"""
