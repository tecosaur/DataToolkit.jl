function _read_jld2 end # Implemented in `../../../ext/JLD2Ext.jl`
function _write_jld2 end # Implemented in `../../../ext/JLD2Ext.jl`

function load(loader::DataLoader{:jld2}, from::FilePath, R::Type)
    @require JLD2
    key = get(loader, "key", nothing)
    if isnothing(key)
        @assert R == Dict{String, Any}
        invokelatest(_read_jld2, from.path)::R
    elseif key isa String
        invokelatest(_read_jld2, from.path, key)::R
    elseif key isa Vector
        invokelatest(_read_jld2, from.path, key...)::R
    else
        throw(InvalidParameterType(loader, "key", Union{String, Vector, Nothing}))
    end
end

supportedtypes(::Type{DataLoader{:jld2}}, spec::Dict{String, Any}) =
    [QualifiedType(if haskey(spec, "key") Any else Dict{String, Any} end)]

function save(::DataLoader{:jld2}, info::Dict{String, Any}, dest::FilePath)
    @require JLD2
    invokelatest(_write_jld2, dest.path, info)
end

createpriority(::Type{DataLoader{:jld2}}) = 10

create(::Type{DataLoader{:jld2}}, source::String) =
    !isnothing(match(r"\.jld2$"i, source))

Store.shouldstore(::DataLoader{:jld2}, ::Type) = false

const JLD2_DOC = md"""
Load and write data in the JLD2 format

# Input/output

The `jld2` driver expects data to be provided via a `FilePath`.

# Required packages

- `JLD2`

# Parameters

- `key`: A particular key, or list of keys, to load from the JLD2 dataset.

# Usage examples

```toml
[[sample.loader]]
driver = "jld2"
```
"""
