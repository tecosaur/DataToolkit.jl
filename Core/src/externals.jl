struct DriverUnimplementedException <: Exception
    transform::AbstractDataTransformer
    driver::Symbol
    method::Symbol
end

Base.read(f::AbstractString, ::Type{DataCollection}; writer::Union{Function, Nothing} = self -> write(f, self)) =
    read(open(f, "r"), DataCollection; writer)

Base.read(io::IO, ::Type{DataCollection}; writer::Union{Function, Nothing}=nothing) =
    DataCollection(TOML.parse(io); writer)

function Base.read(dataset::DataSet, as::Type)
    loaderfuncsall = methods(load, Tuple{DataLoader, Any, Any})
    qtype = QualifiedType(as)
    # Surely there's a better way?
    potential_loaders =
        filter(loader -> qtype in loader.supports, dataset.loaders)
    for loader in potential_loaders
        loaderfuncs = filter(l -> loader isa Base.unwrap_unionall(l.sig).types[2],
                             loaderfuncsall)
        for storage in dataset.storage
            for lfunc in loaderfuncs
                lsig = Base.unwrap_unionall(lfunc.sig)
                for stype in convert.(Type, storage.supports)
                    if stype isa lsig.types[3] || stype <: lsig.types[3]
                        datahandle = open(dataset, stype; write = false)
                        if !isnothing(datahandle)
                            return dataset.collection.transduce(
                                load, loader, datahandle, as)
                        end
                    end
                end
            end
        end
    end
    if length(potential_loaders) == 0
        error("There are no loaders that can provide $as")
    else
        error("There are no availible storage backends that can be used by a loader for $as.")
    end
end

function load(loader::DataLoader{driver}, source, as) where {driver}
    error("No $driver loader is defined")
end

function Base.open(data::DataSet, as::Type; write::Bool=false)
    qtype = QualifiedType(as)
    for storage_provider in data.storage
        if qtype in storage_provider.supports
            return storage(storage_provider, as)
        end
    end
end
# Base.open(data::DataSet, qas::QualifiedType; write::Bool) =
#     open(convert(Type, qas), data; write)

function storage(storer::DataStorage, as::Type; write::Bool=false)
    if write
        tostorage(storer, as)
    else
        fromstorage(storer, as)
    end
end

function fromstorage(::DataStorage{driver}, ::Type) where {driver}
    error("No $driver storage reader is defined")
end

function tostorage(::DataStorage{driver}, ::Type) where {driver}
    error("No $driver storage writer is defined")
end

function Base.write(data::DataSet, info::T) where {T}

end

function writeout(::DataWriter{driver}, info::T) where {driver, T}
    error("No $driver writer is defined")
end













function getloaders(loader::DataLoader, )

end

function getstorage()

end
