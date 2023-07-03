function load(loader::DataLoader{:jld2}, from::FilePath, R::Type)
    @import JLD2
    key = get(loader, "key", nothing)
    if isnothing(key)
        @assert R == Dict{String, Any}
        JLD2.load(from.path)
    elseif key isa String
        JLD2.load(from.path, key)::R
    elseif key isa Vector
        JLD2.load(from.path, key...)::R
    else
        throw(InvalidParameterType(loader, "key", Union{String, Vector, Nothing}))
    end
end

supportedtypes(::Type{DataLoader{:jld2}}, spec::SmallDict{String, Any}) =
    [QualifiedType(if haskey(spec, "key") Any else Dict{String, Any} end)]

function save(::DataLoader{:jld2}, info::Dict{String, Any}, dest::FilePath)
    @import JLD2
    JLD2.save(dest.path, info)
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
