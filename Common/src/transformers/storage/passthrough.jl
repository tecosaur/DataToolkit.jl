function getstorage(storage::DataStorage{:passthrough}, T::Type)
    collection = storage.dataset.collection
    ident = @advise collection parse(Identifier, @getparam storage."source"::String)
    read(resolve(collection, ident, resolvetype=false), T)
end

# To avoid method ambiguity with the fallback methods
getstorage(storage::DataStorage{:passthrough}, T::Type{Vector{UInt8}}) =
    invoke(getstorage, Tuple{typeof(storage), Type}, storage, T)
getstorage(storage::DataStorage{:passthrough}, T::Type{String}) =
    invoke(getstorage, Tuple{typeof(storage), Type}, storage, T)
getstorage(storage::DataStorage{:passthrough}, T::Type{IO}) =
    invoke(getstorage, Tuple{typeof(storage), Type}, storage, T)

function supportedtypes(::Type{DataStorage{:passthrough}}, params::Dict{String, Any}, dataset::DataSet)
    ident = @advise dataset parse(Identifier, get(params, "source", "")::String)
    if !isnothing(ident.type)
        [ident.type]
    else
        [QualifiedType(Any)]
    end
end

DataToolkitCore.add_dataset_refs!(acc::Vector{Identifier}, storage::DataStorage{:passthrough}) =
    DataToolkitCore.add_dataset_refs!(acc, parse(Identifier, get(storage, "source")))

createpriority(::Type{DataStorage{:passthrough}}) = 60

function createauto(::Type{DataStorage{:passthrough}}, source::String)
    if try resolve(source); true catch _ false end
        Dict("source" => source)
    end
end

# TODO putstorage

const PASSTHROUGH_S_DOC = md"""
Use a data set as a storage source

The `passthrough` storage driver enables dataset redirection by offering the
loaded result of another data set as a *read-only* storage transformer.

Write capability may be added in future.

# Parameters

- `source`: The identifier of the source dataset to be loaded.

# Usage examples

```toml
[[iris2.storage]]
driver = "passthrough"
source = "iris1"
```
"""
