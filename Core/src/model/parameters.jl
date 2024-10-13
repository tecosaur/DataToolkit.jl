"""
    dataset_parameters(source::Union{DataCollection, DataSet, DataTransformer},
                       action::Val{:extract|:resolve|:encode}, value::Any)

Obtain a form (depending on `action`) of `value`, a property within `source`.

## Actions

**`:extract`**  Look for [`DataSet`](@ref) references ("[`$(DATASET_REFERENCE_WRAPPER[1])…$(DATASET_REFERENCE_WRAPPER[2])`](@ref DATASET_REFERENCE_WRAPPER)") within
  `value`, and turn them into [`Identifier`](@ref)s (the inverse of `:encode`).

**`:resolve`**  Look for [`Identifier`](@ref)s in `value`, and resolve them to the
  referenced [`DataSet`](@ref)/value.

**`:encode`**  Look for [`Identifier`](@ref)s in `value`, and turn them into [`DataSet`](@ref) references
  (the inverse of `:extract`).
"""
function dataset_parameters(collection::DataCollection, action::Val, params::Dict{String,Any})
    d = newdict(String, Any, length(params))
    for (key, value) in params
        d[key] = dataset_parameters(collection, action, value)
    end
    d
end

function dataset_parameters(collection::DataCollection, action::Val, param::Vector)
    map(value ->  dataset_parameters(collection, action, value), param)
end

dataset_parameters(::DataCollection, ::Val, value::Any) = value

dataset_parameters(dataset::DataSet, action::Val, params::Any) =
    dataset_parameters(dataset.collection, action, params)

dataset_parameters(dt::DataTransformer, action::Val, params::Any) =
    dataset_parameters(dt.dataset.collection, action, params)

function dataset_parameters(collection::DataCollection, ::Val{:extract}, param::String)
    dsid_match = match(DATASET_REFERENCE_REGEX, param)
    if !isnothing(dsid_match)
        @advise collection parse_ident(dsid_match.captures[1])::Identifier
    else
        param
    end
end

function dataset_parameters(collection::DataCollection, ::Val{:resolve}, param::Identifier)
    resolve(collection, param)
end

function dataset_parameters(collection::DataCollection, ::Val{:encode}, param::Identifier)
    string(DATASET_REFERENCE_WRAPPER[1],
           (@advise collection string(param)),
           DATASET_REFERENCE_WRAPPER[2])
end

function Base.get(dataobj::Union{DataSet, DataCollection, <:DataTransformer},
                  property::AbstractString, default=nothing)
    if haskey(dataobj.parameters, property)
        dataset_parameters(dataobj, Val(:resolve), dataobj.parameters[property])
    else
        default
    end
end

Base.get(dataobj::Union{DataSet, DataCollection, <:DataTransformer},
         ::typeof(:)) =
    dataset_parameters(dataobj, Val(:resolve), dataobj.parameters)

# Nice extra

function referenced_datasets(dataset::DataSet)
    dataset_references = Identifier[]
    add_dataset_refs!(dataset_references, dataset.parameters)
    for paramsource in vcat(dataset.storage, dataset.loaders, dataset.writers)
        add_dataset_refs!(dataset_references, paramsource)
    end
    map(r -> resolve(dataset.collection, r, resolvetype=false), dataset_references) |> unique!
end

add_dataset_refs!(acc::Vector{Identifier}, @nospecialize(dt::DataTransformer)) =
    add_dataset_refs!(acc, dt.parameters)

add_dataset_refs!(acc::Vector{Identifier}, props::Dict) =
    for val in values(props)
        add_dataset_refs!(acc, val)
    end

add_dataset_refs!(acc::Vector{Identifier}, props::Vector) =
    for val in props
        add_dataset_refs!(acc, val)
    end

add_dataset_refs!(acc::Vector{Identifier}, ident::Identifier) =
    push!(acc, ident)

add_dataset_refs!(::Vector{Identifier}, ::Any) = nothing
