function load(::DataLoader{:passthrough}, from::T, ::Type{T}) where {T <: Any}
    Some(from)
end

# To avoid method ambiguity with the fallback methods
load(::DataLoader{:passthrough}, from::IO, T::Type{IO}) =
    Some(from)
load(::DataLoader{:passthrough}, from::Vector{UInt8}, T::Type{Vector{UInt8}}) =
    Some(from)
load(::DataLoader{:passthrough}, from::String, T::Type{String}) =
    Some(from)

function save(::DataWriter{:passthrough}, dest, info::Any)
    dest = info
end

function save(::DataWriter{:passthrough}, dest::IO, info::Any)
    write(dest, info)
end

supportedtypes(::Type{DataLoader{:passthrough}}, ::Dict{String, Any}, dataset::DataSet) =
    mapreduce(s -> s.type, vcat, dataset.storage) |> unique

createpriority(::Type{DataLoader{:passthrough}}) = 20

createauto(::Type{DataLoader{:passthrough}}, source::String, dataset::DataSet) =
    any(isa.(dataset.storage, DataStorage{:raw}))

const PASSTHROUGH_L_DOC = md"""
Simply passes on data to/from the storage backend

# Input/output

Identical to that of the storage.

# Usage examples

```toml
[[magicvalue.loader]]
driver = "passthrough"
```
"""
