Identifier(ident::Identifier, params::Dict{String, Any}; replace::Bool=false) =
    Identifier(ident.collection, ident.dataset, ident.type,
               if replace || isempty(ident.parameters);
                   params
               else
                   merge(ident.parameters, params)
               end)

Identifier(ident::Identifier, ::Nothing; replace::Bool=false) =
    if replace
        Identifier(ident, Dict{String, Any}(); replace)
    else
        ident
    end

# Identifier(spec::AbstractString) = parse(Identifier, spec)

Identifier(spec::AbstractString, params::Dict{String, Any}) =
    Identifier(parse(Identifier, spec), params)

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
                param in ignore || d.parameters[param] == value,
                ident.parameters)
        end
    matchingdatasets = collection.datasets |> filter_nameid |> filter_type
    matchingdatasets, ignoreparams =
        @advise collection refine(matchingdatasets, ident, String[])
    matchingdatasets = filter_parameters(matchingdatasets, ignoreparams)
    # TODO non-generic errors
    if length(matchingdatasets) == 1
        dataset = first(matchingdatasets)
        if !isnothing(ident.type) && resolvetype
            read(dataset, typeify(ident.type, mod=collection.mod))
        else
            dataset
        end
    elseif length(matchingdatasets) == 0 && requirematch
        throw(error("No datasets from '$(collection.name)' matched the identifier $ident"))
    elseif length(matchingdatasets) > 1
        throw(error("Multiple datasets from '$(collection.name)' matched the identifier $ident"))
    end
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
        throw(error("No datasets in $(join(''' .* getproperty.(stack, :name) .* ''', ", ", ", or ")) matched the identifier $ident"))
    end

"""
    resolve(identstr::AbstractString, parameters::Union{Dict{String, Any}, Nothing}=nothing;
            resolvetype::Bool=true, stack::Vector{DataCollection}=STACK)

Attempt to resolve the identifier given by `identstr` and `parameters` against
each layer of the data `stack` in turn.
"""
function resolve(identstr::AbstractString, parameters::Union{Dict{String, Any}, Nothing}=nothing;
                 resolvetype::Bool=true, stack::Vector{DataCollection}=STACK)
    if (cname = parse(Identifier, identstr).collection) |> !isnothing
        collection = getlayer(cname)
        ident = Identifier((@advise collection parse(Identifier, identstr)),
                           parameters)
        resolve(collection, ident; resolvetype)
    else
        for collection in stack
            ident = Identifier((@advise collection parse(Identifier, identstr)),
                               parameters)
            result = resolve(collection, ident; resolvetype, requirematch=false)
            !isnothing(result) && return result
        end
        throw(error("No datasets in $(join(''' .* getproperty.(stack, :name) .* ''', ", ", ", or ")) matched the identifier $ident"))
    end
end
