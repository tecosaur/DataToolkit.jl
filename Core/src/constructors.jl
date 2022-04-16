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

function Identifier(dsi::String)
    try
    layer, rest = match(r"^(?:([^:]+):)?([^:].*)?$", dsi).captures
    dataset, rest = match(r"^([^:@#]+)(.*)$", rest).captures
    # version, rest = match(r"^(?:@([0-9\.]+[a-z\-]*|latest))?(.*)$", rest).captures
    # hash, rest = match(r"^(?:#([0-9a-f]+))?(.*)$", rest).captures
    dtype = match(r"^(?:::([A-Za-z0-9\.]+))?$", rest).captures[1]
    dataset_isuuid = !isnothing(match(r"^[0-9a-f]{8}-[0-9a-f]{4}$", dataset))
    Identifier(layer,
               if dataset_isuuid
                   UUID(dataset)
               else dataset end,
               if !isnothing(dtype)
                   QualifiedType(dtype)
               end,
               Dict{String, Any}())
    catch _
        throw(ArgumentError("Data set identifier \"$dsi\" did not follow the required form."))
    end
end

function (ADT::Type{<:AbstractDataTransformer})(
   @nospecialize(dataset::Union{DataSet, DataCollection}), spec::Dict{String, Any})
    driver = if ADT isa DataType
        first(ADT.parameters)
    else
        Symbol(get(spec, "driver", "unspecified"))
    end
    supports = get(spec, "supports", String[]) .|> QualifiedType
    priority = get(spec, "priority", DEFAULT_DATATRANSFORMER_PRIORITY)
    arguments = copy(spec)
    delete!(arguments, "driver")
    delete!(arguments, "supports")
    delete!(arguments, "priority")
    ADT{driver}(dataset, supports, priority, arguments)
end

DataStorage{driver}(dataset::Union{DataSet, DataCollection},
                    supports::Vector{QualifiedType}, priority::Int,
                    arguments::Dict{String, Any}) where {driver} =
    DataStorage{driver, typeof(dataset)}(dataset, supports, priority, arguments)

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

function DataCollection(spec::Dict{String, Any}; writer::Union{Function, Nothing}=nothing)
    plugins = get(get(spec, "data", Dict("data" => Dict())), "plugins", String[])
    DataTransducerAmalgamation(plugins)(fromtoml, DataCollection, spec; writer)
end

function fromtoml(::Type{DataCollection}, spec::Dict{String, Any}; writer::Union{Function, Nothing}=nothing)
    version = get(spec, "data_config_version", LATEST_DATA_CONFIG_VERSION)
    name = get(spec, "name", nothing)
    uuid = UUID(get(spec, "uuid", uuid4()))
    parameters = get(spec, "data", Dict{String, Any}())
    plugins = get(parameters, "plugins", String[])
    defaults = merge(DATASET_DEFAULTS,
                     get(parameters, "defaults", Dict{String, Any}()))
    stores = get(parameters, "store", Dict{String, Any}())
    for reserved in ("plugins", "defaults", "store")
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
    collection = DataCollection(version, name, uuid, plugins, defaults,
                                DataStore[], parameters, DataSet[], writer,
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
    collection.transduce(fromtoml, DataSet, collection, name, spec)
end

function fromtoml(::Type{DataSet}, collection::DataCollection, name::String, spec::Dict{String, Any})
    uuid = UUID(get(spec, "uuid", uuid4()))
    store = get(spec, "store", collection.defaults["store"])
    parameters = copy(spec)
    for reservedname in DATA_CONFIG_RESERVED_ATTRIBUTES[:dataset]
        delete!(parameters, reservedname)
    end
    dataset = DataSet(collection, name, uuid, store, parameters, DataStorage[], DataLoader[], DataWriter[])
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
