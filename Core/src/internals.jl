# ------------------
# QualifiedType utils
# ------------------

function Base.convert(::Type{Type}, qt::QualifiedType)
    try
        getfield(getfield(Main, qt.parentmodule), qt.name)
    catch e
        if !(e isa UndefVarError)
            rethrow(e)
        end
    end
end

function Base.issubset(a::QualifiedType, b::QualifiedType)
    if a == b
        true
    else
        A, B = convert(Type, a), convert(Type, b)
        !any(isnothing, (A, B)) && A <: B
    end
end

Base.issubset(a::QualifiedType, b::Type) = issubset(a, QualifiedType(b))
Base.issubset(a::Type, b::QualifiedType) = issubset(QualifiedType(a), b)

# ------------------
# Grabing collections from the STACK
# ------------------

function getlayer(::Nothing)
    length(STACK) == 0 && throw(error("The data collection stack is empty"))
    first(STACK)
end

function getlayer(name::AbstractString)
    length(STACK) == 0 && throw(error("The data collection stack is empty"))
    matchinglayers = filter(c -> c.name == name, STACK)
    if length(matchinglayers) == 0
        throw(error("No collections within the stack matched the name '$name'"))
    elseif length(matchinglayers) > 1
        throw(error("Multiple collections within the stack matched the name '$name'"))
    else
        first(matchinglayers)
    end
end

function getlayer(uuid::UUID)
    length(STACK) == 0 && throw(error("The data collection stack is empty"))
    matchinglayers = filter(c -> c.uuid == uuid, STACK)
    if length(matchinglayers) == 0
        throw(error("No collections within the stack matched the name '$name'"))
    else
        first(matchinglayers)
    end
end

# ------------------
# Identifier utils
# ------------------

function Base.string(ident::Identifier)
    string(if !isnothing(ident.collection)
               string(ident.collection, ':')
            else "" end,
           ident.dataset,
           if !isnothing(ident.type)
               "::" * string(ident.type)
           else "" end)
end

function Base.parse(::Type{Identifier}, spec::AbstractString; transduced::Bool=false)
    collection, rest::SubString{String} = match(r"^(?:([^:]+):)?([^:].*)?$", spec).captures
    collection_isuuid = !isnothing(collection) && !isnothing(match(r"^[0-9a-f]{8}-[0-9a-f]{4}$", collection))
    if !isnothing(collection) && !transduced
        return getlayer(collection).transduce(parse, Identifier, spec, transduced=true)
    end
    dataset, rest = match(r"^([^:@#]+)(.*)$", rest).captures
    dtype = match(r"^(?:::([A-Za-z0-9\.]+))?$", rest).captures[1]
    dataset_isuuid = !isnothing(match(r"^[0-9a-f]{8}-[0-9a-f]{4}$", dataset))
    Identifier(if collection_isuuid; UUID(collection) else collection end,
               if dataset_isuuid UUID(dataset) else dataset end,
               if !isnothing(dtype) QualifiedType(dtype) end,
               Dict{String,Any}())
end

function resolve(collection::DataCollection, ident::Identifier; resolvetype::Bool=true)
    collection_mismatch = !isnothing(ident.collection) &&
        if ident.collection isa UUID
            collection.uuid != ident.collection
        else
            collection.name != ident.collection
        end
    if collection_mismatch
        return resolve(getlayer(ident.collection), ident)
    end
    filter_nameid(datasets) =
        if ident.dataset isa UUID
            filter(d -> d.uuid == ident.dataset, datasets)
        else
            filter(d -> d.name == ident.dataset, datasets)
        end
    filter_type(datasets) =
        if isnothing(ident.type)
            datasets
        else
            filter(d -> any(l -> any(t -> t ⊆ ident.type, l.supports),
                                  d.loaders), datasets)
        end
    filter_parameters(datasets) =
        filter(datasets) do d
            all((param, value)::Pair -> d.parameters[param] == value,
                ident.parameters)
        end
    matchingdatasets = collection.datasets |>
        filter_nameid |> filter_type |> filter_parameters
    # TODO non-generic errors
    if length(matchingdatasets) == 0
        throw(error("No datasets from '$(collection.name)' matched the identifier $ident"))
    elseif length(matchingdatasets) > 1
        throw(error("Multiple datasets from '$(collection.name)' matched the identifier $ident"))
    else
        dataset = first(matchingdatasets)
        if !isnothing(ident.type) && resolvetype
            read(dataset, convert(Type, ident.type))
        else
            dataset
        end
    end
end

resolve(ident::Identifier; resolvetype::Bool=true) =
    resolve(getlayer(ident.collection), ident; resolvetype)

# ------------------
# DataSet parameters
# ------------------

function dataset_parameters(collection::DataCollection, action::Val, params::Dict{String,Any})
    Dict{String, Any}(key => dataset_parameters(collection, action, value)
                      for (key, value) in params)
end

function dataset_parameters(collection::DataCollection, action::Val, param::Vector)
    map(value ->  dataset_parameters(collection, action, value), param)
end

dataset_parameters(::DataCollection, ::Val, value::Any) = value

dataset_parameters(dataset::DataSet, action::Val, params::Any) =
    dataset_parameters(dataset.collection, action, params)

function dataset_parameters(::DataCollection, ::Val{:extract}, param::String)
    dsid_match = match(DATASET_REFERENCE_REGEX, param)
    if !isnothing(dsid_match)
        Identifier(dsid_match.captures[1])
    else
        param
    end
end

function dataset_parameters(collection::DataCollection, ::Val{:resolve}, param::Identifier)
    resolve(collection, param)
end

function dataset_parameters(collection::DataCollection, ::Val{:encode}, param::Identifier)
    string(DATASET_REFERENCE_WRAPPER[1],
           collection.transduce(string, param),
           DATASET_REFERENCE_WRAPPER[2])
end

function Base.get(dataobj::Union{DataSet, DataCollection},
                  property::AbstractString, default=nothing)
    if haskey(dataobj.parameters, property)
        dataset_parameters(dataobj, Val(:resolve), dataobj.parameters[property])
    else
        default
    end
end

Base.get(dataobj::Union{DataSet, DataCollection}, ::typeof(:)) =
    dataset_parameters(dataobj, Val(:resolve), dataobj.parameters)

# ------------------
# Data Transducers
# ------------------

Base.methods(dt::DataTransducer) = methods(dt.f)

function (dt::DataTransducer{C, F})(
    (post, func, args, kwargs)::Tuple{Function, Function, Tuple, pairs(NamedTuple)}) where {C, F}
    # @info "Testing $dt"
    if hasmethod(dt.f, Tuple{typeof(post), typeof(func), typeof.(args)...}, keys(kwargs))
        # @info "Applying $dt"
        result = dt.f(post, func, args...; kwargs...)
        if result isa Tuple{Function, Function, Tuple}
            k0 = Base.Pairs{Symbol, Union{}, Tuple{}, NamedTuple{(), Tuple{}}}(NamedTuple(),())
            post, func, args = result
            (post, func, args, k0)
        else
            result
        end
    else
        (post, func, args, kwargs) # act as the identity fuction
    end
end

function Base.getproperty(dta::DataTransducerAmalgamation, prop::Symbol)
    if getfield(dta, :plugins_wanted) != getfield(dta, :plugins_used)
        plugins_availible =
            filter(plugin -> plugin.name in getfield(dta, :plugins_wanted), PLUGINS)
        if getfield.(plugins_availible, :name) != getfield(dta, :plugins_used)
            transducers = getfield.(plugins_availible, :transducers) |>
                Iterators.flatten |> collect
            sort!(transducers, by = t -> t.priority)
            setfield!(dta, :transducers, transducers)
            setfield!(dta, :transduceall, ∘(reverse(transducers)...))
            setfield!(dta, :plugins_used, getfield.(plugins_availible, :name))
        end
    end
    getfield(dta, prop)
end

function (dta::DataTransducerAmalgamation)(
    annotated_func_call::Tuple{Function, Function, Tuple, pairs(NamedTuple)})
    dta.transduceall(annotated_func_call)
end

function (dta::DataTransducerAmalgamation)(func::Function, args...; kwargs...)
    # @info "Calling $func($(join(string.(args), ", ")))"
    post::Function, func2::Function, args2::Tuple, kwargs2::pairs(NamedTuple) =
        dta((identity, func, args, kwargs))
    # @info "Applying $(length(dta.transducers)) transducers to '$func($args, $kwargs)'"
    func2(args2...; kwargs2...) |> post
end
