Identifier(ident::Identifier, params::Dict{String, Any}; replace::Bool=false) =
    Identifier(ident.collection, ident.dataset, ident.type,
               if replace || isempty(ident.parameters);
                   params
               else
                   merge(ident.parameters, params)
               end)

Identifier(ident::Identifier, ::Nothing; replace::Bool=false) =
    if replace
        Identifier(ident, newdict(String, Any, 0); replace)
    else
        ident
    end

"""
    Identifier(dataset::DataSet, collection::Union{Symbol, Nothing}=:name,
               name::Symbol=something(collection, :name))

Create an [`Identifier`](@ref) referring to `dataset`, specifying the collection
`dataset` comes from as well (when `collection` is not `nothing`) as all of its
parameters, but without any type information.

Should `collection` and `name` default to the symbol `:name`, which signals that
the collection and dataset reference of the generated `Identifier` should use
the *name*s of the collection/dataset. If set to `:uuid`, the UUID is used
instead. No other value symbols are supported.
"""
function Identifier(ds::DataSet, collection::Union{Symbol, Nothing}=:name,
                    name::Symbol=something(collection, :name))
    Identifier(
        if collection == :uuid
            ds.collection.uuid
        elseif collection == :name
            ds.collection.name
        elseif isnothing(collection)
        else
            throw(ArgumentError("collection argument must be :uuid, :name, or nothing — not $collection"))
        end,
        if name == :uuid
            ds.uuid
        elseif name == :name
            ds.name
        else
            throw(ArgumentError("name argument must be :uuid or :name — not $name"))
        end,
        nothing,
        ds.parameters)
end

# Identifier(spec::AbstractString) = parse(Identifier, spec)

Identifier(spec::AbstractString, params::Dict{String, Any}) =
    Identifier(parse(Identifier, spec), params)

Base.:(==)(a::Identifier, b::Identifier) =
    getfield.(Ref(a), fieldnames(Identifier)) ==
    getfield.(Ref(b), fieldnames(Identifier))

function Base.string(ident::Identifier)
    string(if !isnothing(ident.collection)
               string(ident.collection, ':')
            else "" end,
           ident.dataset,
           if !isnothing(ident.type)
               "::" * string(ident.type)
           else "" end)
end

"""
    resolve(collection::DataCollection, ident::Identifier;
            resolvetype::Bool=true, requirematch::Bool=true)

Attempt to resolve an identifier (`ident`) to a particular data set.
Matching data sets will searched for from `collection`.

When `resolvetype` is set and `ident` specifies a datatype, the identified data
set will be read to that type.

When `requirematch` is set an error is raised should no dataset match `ident`.
Otherwise, `nothing` is returned.
"""
function resolve(collection::DataCollection, ident::Identifier;
                 resolvetype::Bool=true, requirematch::Bool=true)
    collection_mismatch = !isnothing(ident.collection) &&
        if ident.collection isa UUID
            collection.uuid != ident.collection
        else
            collection.name != ident.collection
        end
    if collection_mismatch
        return resolve(getlayer(ident.collection), ident)
    end
    matchingdatasets = refine(collection, collection.datasets, ident)
    if length(matchingdatasets) == 1
        dataset = first(matchingdatasets)
        if !isnothing(ident.type) && resolvetype
            read(dataset, typeify(ident.type, mod=collection.mod, shoulderror=true))
        else
            dataset
        end
    elseif length(matchingdatasets) == 0 && requirematch
        notypeident = Identifier(ident.collection, ident.dataset, nothing, ident.parameters)
        notypematches = refine(collection, collection.datasets, notypeident)
        if !isempty(notypematches)
            throw(UnsatisfyableTransformer(first(notypematches), DataLoader, ident.type))
        else
            throw(UnresolveableIdentifier{DataSet}(string(notypeident), collection))
        end
    elseif length(matchingdatasets) > 1
        throw(AmbiguousIdentifier((@advise collection string(ident)::String),
                                  matchingdatasets, collection))
    end
end

"""
    refine(collection::DataCollection, datasets::Vector{DataSet}, ident::Identifier)

Filter `datasets` (from `collection`) to data sets than match the identifier `ident`.

This function contains an advise entrypoint where plugins can apply further filtering,
applied to the method `refine(::Vector{DataSet}, ::Identifier, ::Vector{String})`.
"""
function refine(collection::DataCollection, datasets::Vector{DataSet}, ident::Identifier)
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
            filter(d -> any(l -> any(t -> ⊆(t, ident.type, mod=collection.mod), l.type),
                            d.loaders), datasets)
        end
    filter_parameters(datasets, ignore) =
        filter(datasets) do d
            all((param, value)::Pair ->
                param in ignore || get(d, param) == value,
                ident.parameters)
        end
    matchingdatasets = datasets |> filter_nameid |> filter_type
    matchingdatasets, ignoreparams =
        @advise collection refine(matchingdatasets, ident, String[])::Tuple{Vector{DataSet}, Vector{String}}
    filter_parameters(matchingdatasets, ignoreparams)
end

"""
    refine(datasets::Vector{DataSet}, ::Identifier, ignoreparams::Vector{String})

This is a stub function that exists soley as as an advise point for data set
filtering during resolution of an identifier.
"""
refine(datasets::Vector{DataSet}, ::Identifier, ignoreparams::Vector{String}) =
    (datasets, ignoreparams)

"""
    resolve(ident::Identifier; resolvetype::Bool=true, stack=STACK)

Attempt to resolve `ident` using the specified data layer, if present, trying
every layer of the data stack in turn otherwise.
"""
resolve(ident::Identifier; resolvetype::Bool=true, stack::Vector{DataCollection}=STACK) =
    if !isnothing(ident.collection)
        resolve(getlayer(ident.collection), ident; resolvetype)
    else
        for collection in stack
            result = resolve(collection, ident; resolvetype, requirematch=false)
            if !isnothing(result)
                return result
            end
        end
        throw(UnresolveableIdentifier{DataSet}(string(ident)))
    end

"""
    resolve(identstr::AbstractString, parameters::Union{Dict{String, Any}, Nothing}=nothing;
            resolvetype::Bool=true, stack::Vector{DataCollection}=STACK)

Attempt to resolve the identifier given by `identstr` and `parameters` against
each layer of the data `stack` in turn.
"""
function resolve(identstr::AbstractString, parameters::Union{Dict{String, Any}, Nothing}=nothing;
                 resolvetype::Bool=true, stack::Vector{DataCollection}=STACK)
    isempty(stack) && throw(EmptyStackError())
    if (cname = parse(Identifier, identstr).collection) |> !isnothing
        collection = getlayer(cname)
        ident = Identifier((@advise collection parse_ident(identstr)::Identifier),
                           parameters)
        resolve(collection, ident; resolvetype)
    else
        for collection in stack
            ident = Identifier((@advise collection parse_ident(identstr)::Identifier),
                               parameters)
            result = resolve(collection, ident; resolvetype, requirematch=false)
            !isnothing(result) && return result
        end
        throw(UnresolveableIdentifier{DataSet}(String(identstr)))
    end
end
