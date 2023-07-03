function getstorage(storage::DataStorage{:passthrough}, T::Type)
    collection = storage.dataset.collection
    ident = @advise collection parse(Identifier, @getparam storage."source"::String)
    read(resolve(collection, ident), T)
end

createpriority(::Type{<:DataStorage{:passthrough}}) = 60

function create(::Type{<:DataStorage{:passthrough}}, source::String)
    if try resolve(source); true catch _ false end
        ["source" => source]
    end
end

# Ensure that `passthrough` storage registers dependents in the recursive hashing interface.

# interface, as well as contextual hashing.

function Store.rhash(collection::DataCollection, storage::DataStorage{:passthrough}, h::UInt)
    ident = @advise collection parse(Identifier, @getparam storage."source"::String)
    sourceh = Store.rhash(collection, ident, h)
    invoke(Store.rhash, Tuple{DataCollection, AbstractDataTransformer, UInt},
           collection, storage, sourceh)
end

Store.shouldstore(::DataStorage{:passthrough}) = false

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
