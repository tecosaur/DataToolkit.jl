function getstorage(storage::DataStorage{:passthrough}, T::Type)
    collection = storage.dataset.collection
    ident = @advise collection parse(Identifier, get(storage, "source"))
    read(resolve(collection, ident), T)
end

createpriority(::Type{<:DataStorage{:passthrough}}) = 60

function create(::Type{<:DataStorage{:passthrough}}, source::String)
    if try resolve(source); true catch _ false end
        Dict{String, Any}("source" => source)
    end
end

# Ensure that `passthrough` storage registers dependents in the AbstractTrees
# interface, as well as contextual hashing.

DataToolkitBase.add_datasets!(acc::Vector{Identifier}, storage::DataStorage{:passthrough}) =
    DataToolkitBase.add_datasets!(acc, parse(Identifier, get(storage, "source")))

function chash(collection::DataCollection, storage::DataStorage{:passthrough}, h::UInt)
    ident = @advise collection parse(Identifier, get(storage, "source"))
    sourceh = chash(collection, ident, h)
    invoke(chash, Tuple{DataCollection, AbstractDataTransformer, UInt},
           collection, storage, sourceh)
end

# TODO putstorage
