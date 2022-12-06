getstorage(storage::DataStorage{:passthrough}, T::Type) =
    read(resolve(parse(Identifier, get(storage, "source"))), T)

createpriority(::Type{<:DataStorage{:passthrough}}) = 60

function create(::Type{<:DataStorage{:passthrough}}, source::String)
    if try resolve(parse(Identifier, source)); true catch _ false end
        Dict{String, Any}("source" => source)
    end
end

# Ensure that `passthrough` storage registers dependents in the AbstractTrees
# interface, as well as contextual hashing.

DataToolkitBase.add_datasets!(acc::Vector{Identifier}, storage::DataStorage{:passthrough}) =
    DataToolkitBase.add_datasets!(acc, parse(Identifier, get(storage, "source")))

function chash(collection::DataCollection, storage::DataStorage{:passthrough}, h::UInt)
    sourceh = chash(collection, parse(Identifier, get(storage, "source")), h)
    invoke(chash, Tuple{DataCollection, AbstractDataTransformer, UInt},
           collection, storage, sourceh)
end

# TODO putstorage
