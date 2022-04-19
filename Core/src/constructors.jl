function QualifiedType(t::AbstractString)
    components = split(t, '.')
    parentmodule, name = if length(components) == 1
        n = Symbol(components[1])
        Symbol(Base.binding_module(Main, n)), n
    elseif length(components) == 2
        Symbol.(components)
    else
        Symbol.(components[end-1:end])
    end
    QualifiedType(parentmodule, name)
end

QualifiedType(::Type{T}) where {T} =
    QualifiedType(Symbol(parentmodule(T)), nameof(T))

QualifiedType(qt::QualifiedType) = qt

Identifier(ident::Identifier, params::Dict{String, Any}; replace::Bool=false) =
    Identifier(ident.collection,
               ident.dataset,
               ident.type,
               if replace; params else merge(ident.parameters, params) end)

Identifier(spec::AbstractString) = parse(Identifier, spec)

Identifier(spec::AbstractString, params::Dict{String, Any}) =
    Identifier(Identifier(spec), params)

# function (ADT::Type{<:AbstractDataTransformer})(collection::DataCollection, spec::Dict{String, Any})
#     collection.transduce(fromspec, ADT, collection, spec)
# end

function (ADT::Type{<:AbstractDataTransformer})(dataset::DataSet, spec::Dict{String, Any})
    dataset.collection.transduce(fromspec, ADT, dataset, spec)
end

function fromspec(ADT::Type{<:AbstractDataTransformer},
                  dataset::DataSet, spec::Dict{String, Any})
    driver = if ADT isa DataType
        first(ADT.parameters)
    else
        Symbol(spec["driver"])
    end
    supports = get(spec, "supports", String[]) .|> QualifiedType
    priority = get(spec, "priority", DEFAULT_DATATRANSFORMER_PRIORITY)
    parameters = copy(spec)
    delete!(parameters, "driver")
    delete!(parameters, "supports")
    delete!(parameters, "priority")
    dataset.collection.transduce(
        identity,
        ADT{driver}(dataset, supports, priority,
                    dataset_parameters(dataset, Val(:extract), parameters)))
end

DataStorage{driver}(dataset::Union{DataSet, DataCollection},
                    supports::Vector{QualifiedType}, priority::Int,
                    parameters::Dict{String, Any}) where {driver} =
    DataStorage{driver, typeof(dataset)}(dataset, supports, priority, parameters)

DataTransducer(f::Function) =
    DataTransducer(DEFAULT_DATATRANSDUCER_PRIORITY, f)

DataTransducerAmalgamation(plugins::Vector{String}) =
    DataTransducerAmalgamation(identity, DataTransducer[], plugins, String[])

DataTransducerAmalgamation(collection::DataCollection) =
    DataTransducerAmalgamation(collection.plugins)

DataTransducerAmalgamation(dta::DataTransducerAmalgamation) = # for re-building
    DataTransducerAmalgamation(dta.plugins_wanted)

function DataStore(collection::DataCollection, spec::Dict{String, Any})
    DataStore(get(spec, "name", "global"),
              DataStorage(collection, delete!(copy(spec), "name")))
end

function DataCollection(spec::Dict{String, Any}; path::Union{String, Nothing}=nothing)
    plugins = get(get(spec, "data", Dict("data" => Dict())), "plugins", String[])
    DataTransducerAmalgamation(plugins)(fromspec, DataCollection, spec; path)
end

function fromspec(::Type{DataCollection}, spec::Dict{String, Any}; path::Union{String, Nothing}=nothing)
    version = get(spec, "data_config_version", LATEST_DATA_CONFIG_VERSION)
    name = get(spec, "name", nothing)
    uuid = UUID(get(spec, "uuid", uuid4()))
    plugins = get(spec, "plugins", String[])
    parameters = get(spec, "data", Dict{String, Any}())
    stores = get(parameters, "store", Dict{String, Any}())
    for reserved in ("store")
        delete!(parameters, reserved)
    end
    unavailible_plugins = setdiff(plugins, getproperty.(PLUGINS, :name))
    if length(unavailible_plugins) > 0
        @warn string("The ", join(unavailible_plugins, ", ", ", and "),
                     " plugin", if length(unavailible_plugins) == 1
                         " is" else "s are" end,
                     " not availible at the time of loading '$name'.",
                     "\n It is highly recommended that all plugins are loaded",
                     " prior to DataCollections.")
    end
    collection = DataCollection(version, name, uuid, plugins,
                                DataStore[], parameters, DataSet[], path,
                                DataTransducerAmalgamation(plugins))
    for store in stores
        push!(collection.stores, DataStore(collection, store))
    end
    # Construct the data sets
    datasets = copy(spec)
    for reservedname in DATA_CONFIG_RESERVED_ATTRIBUTES[:collection]
        delete!(datasets, reservedname)
    end
    for (name, dspecs) in datasets
        for dspec in dspecs
            push!(collection.datasets, DataSet(collection, name, dspec))
        end
    end
    collection.transduce(identity, collection)
end

function DataSet(collection::DataCollection, name::String, spec::Dict{String, Any})
    collection.transduce(fromspec, DataSet, collection, name, spec)
end

function fromspec(::Type{DataSet}, collection::DataCollection, name::String, spec::Dict{String, Any})
    uuid = UUID(get(spec, "uuid", uuid4()))
    store = get(spec, "store", collection.defaults["store"])
    parameters = copy(spec)
    for reservedname in DATA_CONFIG_RESERVED_ATTRIBUTES[:dataset]
        delete!(parameters, reservedname)
    end
    dataset = DataSet(collection, name, uuid, store,
                      dataset_parameters(collection, Val(:extract), parameters),
                      DataStorage[], DataLoader[], DataWriter[])
    for (attr, afield, atype) in [("storage", :storage, DataStorage),
                                  ("loader", :loaders, DataLoader),
                                  ("writer", :writers, DataWriter)]
        for aspec in get(spec, attr, Dict{String, Any}[])
            push!(getfield(dataset, afield), atype(dataset, aspec))
        end
        sort!(getfield(dataset, afield), by=a->a.priority)
    end
    collection.transduce(identity, dataset)
end
