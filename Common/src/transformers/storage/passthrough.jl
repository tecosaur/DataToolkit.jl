function getstorage(storage::DataStorage{:passthrough}, T::Type)
    collection = storage.dataset.collection
    ident = @advise collection parse(Identifier, get(storage, "source"))
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
    ident = @advise collection parse(Identifier, get(storage, "source"))
    sourceh = Store.rhash(collection, ident, h)
    invoke(Store.rhash, Tuple{DataCollection, AbstractDataTransformer, UInt},
           collection, storage, sourceh)
end

Store.shouldstore(::DataStorage{:passthrough}) = false

# TODO putstorage
