# ---------------
# QualifiedType
# ---------------

function Base.parse(::Type{QualifiedType}, spec::AbstractString)
    if haskey(QUALIFIED_TYPE_SHORTHANDS.forward, spec)
        return QUALIFIED_TYPE_SHORTHANDS.forward[spec]
    end
    components, parameters = let cbsplit = split(spec, '{', limit=2)
        if length(cbsplit) == 1
            split(cbsplit[1], '.'), Tuple{}()
        else
            split(cbsplit[1], '.'),
            # REVIEW should this support commas within type parameters?
            # e.g. A{B,C{D,E}}. This feels like probably a bit much.
            Tuple(map(p -> @something(tryparse(Int, p),
                                      tryparse(Float64, p),
                                      if first(p) == ':'
                                          Symbol(p[2:end])
                                      end,
                                      parse(QualifiedType, p)),
                      split(cbsplit[2][begin:end-1], r", ?")))
        end
    end
    parentmodule, name = if length(components) == 1
        n = Symbol(components[1])
        Symbol(Base.binding_module(Main, n)), n
    elseif length(components) == 2
        Symbol.(components)
    else
        Symbol.(components[end-1:end])
    end
    QualifiedType(parentmodule, name, parameters)
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
    dtype = match(r"^(?:::([A-Za-z0-9{, }\.]+))?$", rest).captures[1]
    Identifier(if collection_isuuid; UUID(collection) else collection end,
               something(tryparse(UUID, dataset), dataset),
               if !isnothing(dtype) parse(QualifiedType, dtype) end,
               Dict{String,Any}())
end

# ---------------
# DataTransformers
# ---------------

"""
    supportedtypes(ADT::Type{<:AbstractDataTransformer})::Vector{QualifiedType}
Return a list of types supported by the data transformer `ADT`.

This is used as the default value for the `support` key in the Data TOML.
The list of types is dynamically generated based on the availible methods for
the data transformer.

In some cases, it makes sense for this to be explicitly defined for a particular
transformer. """
function supportedtypes end # See `interaction/externals.jl` for method definitions.

supportedtypes(ADT::Type{<:AbstractDataTransformer}, _::Dict{String, Any}) =
    supportedtypes(ADT)

(ADT::Type{<:AbstractDataTransformer})(dataset::DataSet, spec::Dict{String, Any}) =
    dataset.collection.advise(fromspec, ADT, dataset, spec)

(ADT::Type{<:AbstractDataTransformer})(dataset::DataSet, spec::String) =
    ADT(dataset, Dict{String, Any}("driver" => spec))

function fromspec(ADT::Type{<:AbstractDataTransformer},
                  dataset::DataSet, spec::Dict{String, Any})
    driver = if ADT isa DataType
        first(ADT.parameters)
    else
        Symbol(lowercase(spec["driver"]))
    end
    support = let spec_support = get(spec, "support", nothing)
        if isnothing(spec_support)
            supportedtypes(if ADT isa DataType ADT else ADT{driver} end, spec)
        elseif spec_support isa Vector
            QualifiedType.(spec_support)
        elseif spec_support isa String
            [QualifiedType(spec_support)]
        else
            error("Parse error: invalid ADT support") # TODO use custom exception type
        end
    end
    priority = get(spec, "priority", DEFAULT_DATATRANSFORMER_PRIORITY)
    parameters = copy(spec)
    delete!(parameters, "driver")
    delete!(parameters, "support")
    delete!(parameters, "priority")
    dataset.collection.advise(
        identity,
        ADT{driver}(dataset, support, priority,
                    dataset_parameters(dataset, Val(:extract), parameters)))
end

# function (ADT::Type{<:AbstractDataTransformer})(collection::DataCollection, spec::Dict{String, Any})
#     collection.advise(fromspec, ADT, collection, spec)
# end

DataStorage{driver}(dataset::Union{DataSet, DataCollection},
                    support::Vector{<:QualifiedType}, priority::Int,
                    parameters::Dict{String, Any}) where {driver} =
    DataStorage{driver, typeof(dataset)}(dataset, support, priority, parameters)

# ---------------
# DataCollection
# ---------------

function DataCollection(spec::Dict{String, Any}; path::Union{String, Nothing}=nothing, mod::Module=Base.Main)
    plugins::Vector{String} = get(get(spec, "config", Dict("config" => Dict())), "plugins", String[])
    DataAdviceAmalgamation(plugins)(fromspec, DataCollection, spec; path, mod)
end

function fromspec(::Type{DataCollection}, spec::Dict{String, Any};
                  path::Union{String, Nothing}=nothing, mod::Module=Base.Main)
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
                                DataAdviceAmalgamation(plugins),
                                mod)
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
