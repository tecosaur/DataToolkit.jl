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

function samecollection(collection::DataCollection, ident::Identifier)
    isnothing(ident.collection) && return true
    if ident.collection isa UUID
        collection.uuid == ident.collection
    else
        collection.name == ident.collection
    end
end

function tryresolve(collection::DataCollection, ident::Identifier)
    if samecollection(collection, ident)
        matchingdatasets = refine(collection, collection.datasets, ident)
        if length(matchingdatasets) == 1
            first(matchingdatasets)
        end
    elseif isnothing(ident.collection) || isempty(STACK)
        nothing
    elseif ident.collection isa UUID
        icol = findall(c -> c.uuid == ident.collection, STACK)
        if length(icol) == 1
            tryresolve(STACK[first(icol)], ident)
        end
    elseif ident.collection isa String
        icol = findall(c -> c.name == ident.collection, STACK)
        if length(icol) == 1
            tryresolve(STACK[first(icol)], ident)
        end
    end
end

"""
    resolve(collection::DataCollection, ident::Identifier)

Attempt to resolve an identifier (`ident`) to a particular data set.
Matching data sets will searched for from `collection`.

If `ident` does not uniquely identify a data set known to `collection`, one
of the following errors will be thrown:
- [`AmbiguousIdentifier`](@ref) if the identifier matches multiple datasets.
- [`UnresolveableIdentifier`](@ref) if the identifier did not match any datasets.
- [`UnsatisfyableTransformer`](@ref) if the identifier did not match any datasets,
  specifically because of the type information in the identifier.
"""
function resolve(collection::DataCollection, ident::Identifier)
    samecollection(collection, ident) ||
        return resolve(getlayer(ident.collection), ident)
    matchingdatasets = refine(collection, collection.datasets, ident)
    if length(matchingdatasets) == 1
        first(matchingdatasets)
    elseif length(matchingdatasets) == 0
        notypeident = Identifier(ident.collection, ident.dataset, nothing, ident.parameters)
        notypematches = refine(collection, collection.datasets, notypeident)
        if !isnothing(ident.type) && !isempty(notypematches)
            throw(UnsatisfyableTransformer(first(notypematches), DataLoader, [ident.type]))
        else
            throw(UnresolveableIdentifier{DataSet}(string(notypeident), collection))
        end
    else # length(matchingdatasets) > 1
        throw(AmbiguousIdentifier((@advise collection string(ident)),
                                  matchingdatasets, collection))
    end
end

function resolve(stack::Vector{DataCollection}, ident::Identifier)
    for collection in stack
        dset = tryresolve(collection, ident)
        !isnothing(dset) && return dset
    end
    throw(UnresolveableIdentifier{DataSet}(string(ident)))
end

resolve(ident::Identifier) = resolve(STACK, ident)

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
        @advise collection refine(matchingdatasets, ident, String[])
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
    resolve([stack], identstr::AbstractString, parameters::Union{Dict{String, Any}, Nothing} = nothing)

Attempt to resolve the identifier given by `identstr` and `parameters` against
each layer of the data `stack` in turn.

Optionally a `Vector` of `DataCollection`s can be provided as `stack`, by
default the global stack is used.
"""
function resolve(stack::Vector{DataCollection}, identstr::AbstractString, parameters::Union{Dict{String, Any}, Nothing} = nothing)
    isempty(stack) && throw(EmptyStackError())
    cname = parse(Identifier, identstr).collection
    if !isnothing(cname)
        collection = getlayer(cname)
        ident = Identifier(@advise(collection, parse_ident(identstr)), parameters)
        resolve(collection, ident)
    else
        for collection in stack
            ident = Identifier(@advise(collection, parse_ident(identstr)), parameters)
            result = tryresolve(collection, ident)
            !isnothing(result) && return result
        end
        throw(UnresolveableIdentifier{DataSet}(String(identstr)))
    end
end

resolve(identstr::AbstractString, parameters::Union{Dict{String, Any}, Nothing} = nothing) =
    resolve(STACK, identstr, parameters)
