# ---------------
# QualifiedType
# ---------------

function Base.parse(::Type{QualifiedType}, spec::AbstractString)
    components = split(spec, '.')
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

# ---------------
# Identifier
# ---------------

function Base.parse(::Type{Identifier}, spec::AbstractString; advised::Bool=false)
    collection, rest::SubString{String} = match(r"^(?:([^:]+):)?([^:].*)?$", spec).captures
    collection_isuuid = !isnothing(collection) && !isnothing(match(r"^[0-9a-f]{8}-[0-9a-f]{4}$", collection))
    if !isnothing(collection) && !advised
        return getlayer(collection).advise(parse, Identifier, spec, advised=true)
    end
    dataset, rest = match(r"^([^:@#]+)(.*)$", rest).captures
    dtype = match(r"^(?:::([A-Za-z0-9\.]+))?$", rest).captures[1]
    dataset_isuuid = !isnothing(match(r"^[0-9a-f]{8}-[0-9a-f]{4}$", dataset))
    Identifier(if collection_isuuid; UUID(collection) else collection end,
               if dataset_isuuid UUID(dataset) else dataset end,
               if !isnothing(dtype) parse(QualifiedType, dtype) end,
               Dict{String,Any}())
end

# ---------------
# DataTransformers
# ---------------

(ADT::Type{<:AbstractDataTransformer})(dataset::DataSet, spec::Dict{String, Any}) =
    dataset.collection.advise(fromspec, ADT, dataset, spec)

(ADT::Type{<:AbstractDataTransformer})(dataset::DataSet, spec::String) =
    ADT(dataset, Dict{String, Any}("driver" => spec))

function fromspec(ADT::Type{<:AbstractDataTransformer},
                  dataset::DataSet, spec::Dict{String, Any})
    driver = if ADT isa DataType
        first(ADT.parameters)
    else
        Symbol(spec["driver"])
    end
    supports = get(spec, "supports", String[]) |>
        s -> if s isa Vector s else [s] end .|> QualifiedType
    priority = get(spec, "priority", DEFAULT_DATATRANSFORMER_PRIORITY)
    parameters = copy(spec)
    delete!(parameters, "driver")
    delete!(parameters, "supports")
    delete!(parameters, "priority")
    dataset.collection.advise(
        identity,
        ADT{driver}(dataset, supports, priority,
                    dataset_parameters(dataset, Val(:extract), parameters)))
end

# function (ADT::Type{<:AbstractDataTransformer})(collection::DataCollection, spec::Dict{String, Any})
#     collection.advise(fromspec, ADT, collection, spec)
# end

DataStorage{driver}(dataset::Union{DataSet, DataCollection},
                    supports::Vector{QualifiedType}, priority::Int,
                    parameters::Dict{String, Any}) where {driver} =
    DataStorage{driver, typeof(dataset)}(dataset, supports, priority, parameters)

# ---------------
# DataCollection
# ---------------

function DataCollection(spec::Dict{String, Any}; path::Union{String, Nothing}=nothing)
    plugins::Vector{String} = get(get(spec, "config", Dict("config" => Dict())), "plugins", String[])
    DataAdviceAmalgamation(plugins)(fromspec, DataCollection, spec; path)
end

function fromspec(::Type{DataCollection}, spec::Dict{String, Any}; path::Union{String, Nothing}=nothing)
    version = get(spec, "data_config_version", LATEST_DATA_CONFIG_VERSION)
    if version != LATEST_DATA_CONFIG_VERSION
        @error "The data collection specificaton uses the v$version format \
                when the v$LATEST_DATA_CONFIG_VERSION format is expected.\n\
                In the future conversion facilities may be implemented, but for now \
                you'll need to manually upgrade the format."
        error("Version mismatch")
    end
    name = get(spec, "name", nothing)
    uuid = UUID(@something get(spec, "uuid", nothing) begin
                    @warn "Data collection '$(something(name, "<unnamed>"))' had no UUID, one has been generated."
                    uuid4()
                end)
    plugins::Vector{String} = get(spec, "plugins", String[])
    parameters = get(spec, "config", Dict{String, Any}())
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
                                parameters, DataSet[], path,
                                DataAdviceAmalgamation(plugins))
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
    collection.advise(identity, collection)
end

# ---------------
# DataSet
# ---------------

function DataSet(collection::DataCollection, name::String, spec::Dict{String, Any})
    collection.advise(fromspec, DataSet, collection, name, spec)
end

function fromspec(::Type{DataSet}, collection::DataCollection, name::String, spec::Dict{String, Any})
    uuid = UUID(@something get(spec, "uuid", nothing) begin
                    @warn "Data set '$name' had no UUID, one has been generated."
                    uuid4()
                end)
    store = get(spec, "store", "DEFAULTSTORE")
    parameters = copy(spec)
    for reservedname in DATA_CONFIG_RESERVED_ATTRIBUTES[:dataset]
        delete!(parameters, reservedname)
    end
    dataset = DataSet(collection, name, uuid,
                      dataset_parameters(collection, Val(:extract), parameters),
                      DataStorage[], DataLoader[], DataWriter[])
    for (attr, afield, atype) in [("storage", :storage, DataStorage),
                                  ("loader", :loaders, DataLoader),
                                  ("writer", :writers, DataWriter)]
        specs = get(spec, attr, Dict{String, Any}[]) |>
            s -> if s isa Vector s else [s] end
        for aspec::Union{String, Dict{String, Any}} in specs
            push!(getfield(dataset, afield), atype(dataset, aspec))
        end
        sort!(getfield(dataset, afield), by=a->a.priority)
    end
    collection.advise(identity, dataset)
end
