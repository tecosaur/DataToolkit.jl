# ---------------
# QualifiedType
# ---------------

function Base.parse(::Type{QualifiedType}, spec::AbstractString)
    if haskey(QUALIFIED_TYPE_SHORTHANDS.forward, spec)
        return QUALIFIED_TYPE_SHORTHANDS.forward[spec]
    end
    components, parameters = let cbsplit = split(spec, '{', limit=2)
        function destruct(param)
            if param isa Number
                param
            elseif param isa QuoteNode
                param.value
            elseif param isa Expr && param.head == :tuple
                Tuple(map(destruct, param.args))
            elseif param isa Symbol
                if haskey(QUALIFIED_TYPE_SHORTHANDS.forward, string(param))
                    QUALIFIED_TYPE_SHORTHANDS.forward[string(param)]
                else
                    QualifiedType(nameof(Base.binding_module(Main, param)),
                                  Symbol[], param, Tuple{}())
                end
            elseif Meta.isexpr(param, :.)
                parse(QualifiedType, string(param))
            elseif Meta.isexpr(param, :<:) && last(param.args) isa Symbol
                TypeVar(if length(param.args) == 2
                            first(param.args)
                        else Symbol("#s0") end,
                        getfield(Main, last(param.args)))
            elseif Meta.isexpr(param, :<:)
                val = trytypeify(parse(QualifiedType, string(last(param.args))))
                isnothing(val) && throw(ArgumentError("Invalid type $(sprint(show, param)) in $(sprint(show, spec))"))
                TypeVar(if length(param.args) == 2
                            first(param.args)
                        else Symbol("#s0") end,
                        val)
            elseif Meta.isexpr(param, :curly)
                base = parse(QualifiedType, string(first(param.args)))
                QualifiedType(base.root, Symbol[], base.name, Tuple(map(destruct, param.args[2:end])))
            else
                throw(ArgumentError("Invalid QualifiedType parameter $(sprint(show, param)) in $(sprint(show, spec))"))
            end
        end
        if length(cbsplit) == 1
            split(cbsplit[1], '.'), Tuple{}()
        else
            typeparams = Meta.parse(spec[1+length(cbsplit[1]):end])
            split(cbsplit[1], '.'), Tuple(map(destruct, typeparams.args))
        end
    end
    root, parents, name = if length(components) == 1
        n = Symbol(components[1])
        nameof(Base.binding_module(Main, n))::Symbol, Symbol[], n
    elseif length(components) == 2
        Symbol(components[1]), Symbol[], Symbol(components[2])
    else
        Symbol(components[1]), map(Symbol, components[2:end-1]), Symbol(components[end])
    end
    QualifiedType(root, parents, name, parameters)
end

# ---------------
# Identifier
# ---------------

function Base.parse(::Type{Identifier}, spec::AbstractString)
    isempty(STACK) && return parse_ident(spec)
    mark = findfirst(':', spec)
    collection = if !isnothing(mark) && (mark == length(spec) || spec[mark+1] != ':')
        cstring = spec[1:prevind(spec, mark)]
        something(tryparse(UUID, cstring), cstring)
    end
    @advise getlayer(collection) parse_ident(spec)
end

function parse_ident(spec::AbstractString)
    mark = findfirst(':', spec)
    collection = if !isnothing(mark) && (mark == length(spec) || spec[mark+1] != ':')
        cstring, spec = spec[begin:prevind(spec, mark)], spec[mark+1:end]
        @something(tryparse(UUID, cstring), String(cstring))
    end
    mark = findfirst(':', spec)
    dataset = if isnothing(mark)
        _, spec = spec, ""
    else
        _, spec = spec[begin:prevind(spec, mark)], spec[mark:end]
    end |> first
    dtype  = if startswith(spec, "::") && length(spec) > 2
        parse(QualifiedType, spec[3:end])
    end
    Identifier(collection, @something(tryparse(UUID, dataset), String(dataset)),
               dtype, newdict(String, Any, 0))
end

# ---------------
# DataTransformers
# ---------------

"""
    supportedtypes(DT::Type{<:DataTransformer}, [spec::Dict{String, Any}, dataset::DataSet]) -> Vector{QualifiedType}

Return a list of types supported by the data transformer `DT`.

This is used as the default value for the `type` key in the Data TOML.
The list of types is dynamically generated based on the available methods for
the data transformer.

In some cases, it makes sense for this to be explicitly defined for a particular
transformer, optionally taking into account information in the `spec` and/or
parent `dataset`.

See also: [`QualifiedType`](@ref), [`DataTransformer`](@ref).
"""
function supportedtypes end # See `interaction/externals.jl` for method definitions.

supportedtypes(DT::Type{<:DataTransformer}, spec::Dict{String, Any}, _::DataSet) =
    supportedtypes(DT, spec)

supportedtypes(DT::Type{<:DataTransformer}, _::Dict{String, Any}) =
    supportedtypes(DT)

(DT::Type{<:DataTransformer})(dataset::DataSet, spec::Dict{String, Any}) =
    @advise fromspec(DT, dataset, spec)

(DT::Type{<:DataTransformer})(dataset::DataSet, driver::String) =
    DT(dataset, Dict{String, Any}("driver" => driver))

"""
    fromspec(DT::Type{<:DataTransformer}, dataset::DataSet, spec::Dict{String, Any})

Create an [`DT`](@ref DataTransformer) of `dataset` according to `spec`.

`DT` can either contain the driver name as a type parameter, or it will be read
from the `"driver"` key in `spec`.
"""
function fromspec(DT::Type{<:DataTransformer}, dataset::DataSet, spec::Dict{String, Any})::DT
    parameters = shrinkdict(spec)
    driver = if DT isa DataType
        driverof(DT)
    elseif haskey(parameters, "driver")
        Symbol(lowercase(parameters["driver"]))
    else
        @warn "$DT for $(sprint(show, dataset.name)) has no driver!"
        :MISSING
    end::Symbol
    if !(DT isa DataType)
        DT = DT{driver}
    end
    ttype = let val = get(parameters, "type", nothing)
        if isnothing(val)
            supportedtypes(DT, parameters, dataset)
        elseif val isa Vector
            [parse(QualifiedType, st) for st in val]
        elseif val isa String
            [parse(QualifiedType, val)]
        else
            @warn "Invalid DT type '$val', ignoring"
        end::Union{Vector{QualifiedType}, Nothing}
    end
    if !isnothing(ttype) && isempty(ttype)
        @warn """Could not find any types that $DT of $(sprint(show, dataset.name)) supports.
                 Consider adding a 'type' parameter."""
    end
    priority = let val = get(parameters, "priority", DEFAULT_DATATRANSFORMER_PRIORITY)
        if val isa Int val else DEFAULT_DATATRANSFORMER_PRIORITY end
    end
    delete!(parameters, "driver")
    delete!(parameters, "type")
    delete!(parameters, "priority")
    @advise dataset identity(
        DT(dataset, ttype, priority,
           dataset_parameters(dataset, Val(:extract), parameters)))
end

# function (DT::Type{<:DataTransformer})(collection::DataCollection, spec::Dict{String, Any})
#     @advise fromspec(DT, collection, spec)
# end

# ---------------
# DataCollection
# ---------------

function DataCollection(spec::Dict{String, Any}; path::Union{String, Nothing}=nothing, mod::Module=Base.Main)
    plugins::Vector{String} = get(get(spec, "config", Dict("config" => Dict())), "plugins", String[])
    AdviceAmalgamation(plugins)(fromspec, DataCollection, spec; path, mod)
end

"""
    fromspec(::Type{DataCollection}, spec::Dict{String, Any};
             path::Union{String, Nothing}=nothing, mod::Module=Base.Main)

Create a [`DataCollection`](@ref) from `spec`.

The `path` and `mod` keywords are used as the values for the corresponding
fields in the [`DataCollection`](@ref).
"""
function fromspec(::Type{DataCollection}, spec::Dict{String, Any};
                  path::Union{String, Nothing}=nothing, mod::Module=Base.Main)
    version = get(spec, "data_config_version", LATEST_DATA_CONFIG_VERSION)
    if version != LATEST_DATA_CONFIG_VERSION
        throw(CollectionVersionMismatch(version))
    end
    name = @something(get(spec, "name", nothing),
                      if !isnothing(path)
                          toml_name = path |> basename |> splitext |> first
                          if toml_name != "Data"
                              toml_name
                          else
                              basename(dirname(path))
                          end
                      end,
                      string(gensym("unnamed"))[3:end])
    uuid = UUID(@something get(spec, "uuid", nothing) begin
                    @info "Data collection '$(something(name, "<unnamed>"))' had no UUID, one has been generated."
                    uuid4()
                end)
    plugins::Vector{String} = get(spec, "plugins", String[])
    parameters = if !haskey(spec, "config")
        Dict{String, Any}()
    elseif spec["config"] isa Dict{String, Any}
        shrinkdict(spec["config"])
    else
        @warn "Invalid config for DataCollection, ignoring"
        Dict{String, Any}()
    end
    unavailable_plugins = setdiff(plugins, [p.name for p in PLUGINS])
    # TODO: Replace `jl_generating_output` with `Base.generating_output` once min Julia >= 1.11
    if length(unavailable_plugins) > 0 && ccall(:jl_generating_output, Cint, ()) == 0
        @warn string("The ", join(unavailable_plugins, ", ", ", and "),
                     " plugin", if length(unavailable_plugins) == 1
                         " is" else "s are" end,
                     " not available at the time of loading '$name'.",
                     "\n It is highly recommended that all plugins are loaded",
                     " prior to DataCollections.")
    end
    collection = DataCollection(version, name, uuid, plugins,
                                parameters, DataSet[], if !isnothing(path); (; path, mtime=mtime(path)) end,
                                AdviceAmalgamation(plugins),
                                mod)
    # Construct the data sets
    datasets = copy(spec)
    for reservedname in DATA_CONFIG_RESERVED_ATTRIBUTES[:collection]
        delete!(datasets, reservedname)
    end
    for (name, dspecs) in datasets
        for dspec in if dspecs isa Vector dspecs else [dspecs] end
            push!(collection.datasets, DataSet(collection, name, dspec))
        end
    end
    @advise identity(collection)
end

# ---------------
# DataSet
# ---------------

function DataSet(collection::DataCollection, name::String, spec::Dict{String, Any})
    @advise fromspec(DataSet, collection, name, spec)
end

"""
    fromspec(::Type{DataSet}, collection::DataCollection, name::String, spec::Dict{String, Any})

Create a [`DataSet`](@ref) for `collection` called `name`, according to `spec`.
"""
function fromspec(::Type{DataSet}, collection::DataCollection, name::String, spec::Dict{String, Any})
    uuid = UUID(@something get(spec, "uuid", nothing) begin
                    @info "Data set '$name' had no UUID, one has been generated."
                    uuid4()
                end)::UUID
    parameters = shrinkdict(spec)
    for reservedname in DATA_CONFIG_RESERVED_ATTRIBUTES[:dataset]
        delete!(parameters, reservedname)
    end
    dataset = DataSet(collection, name, uuid,
                      dataset_parameters(collection, Val(:extract), parameters),
                      DataStorage[], DataLoader[], DataWriter[])
    function addtransformers!(tlist::Vector{T}, ds::DataSet, dspecs::Dict{String, Any}, tname::String) where {T <: DataTransformer}
        tspecs = get(dspecs, tname, Dict{String, Any}[])
        tspecs isa Vector && !isempty(tspecs) || return
        for tspec in tspecs
            tspec isa Dict{String, Any} || continue
            push!(tlist, T(ds, tspec))
        end
        sort!(tlist, by=a->a.priority)
    end
    addtransformers!(dataset.storage, dataset, spec, "storage")
    addtransformers!(dataset.loaders, dataset, spec, "loader")
    addtransformers!(dataset.writers, dataset, spec, "writer")
    @advise identity(dataset)
end
