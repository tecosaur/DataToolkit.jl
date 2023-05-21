"""
    dataset_parameters(source::Union{DataCollection, DataSet, AbstractDataTransformer},
                       action::Val{:extract|:resolve|:encode}, value::Any)

Obtain a form (depending on `action`) of `value`, a property within `source`.

## Actions

**`:extract`**  Look for DataSet references ("$(DATASET_REFERENCE_WRAPPER[1])...$(DATASET_REFERENCE_WRAPPER[2])") within
  `value`, and turn them into `Identifier`s (the inverse of `:encode`).

**`:resolve`**  Look for `Identifier`s in `value`, and resolve them to the
  referenced DataSet/value.

**`:encode`**  Look for `Identifier`s in `value`, and turn them into DataSet references
  (the inverse of `:extract`).
"""
function dataset_parameters(collection::DataCollection, action::Val, params::SmallDict{String,Any})
    SmallDict{String, Any}(
        keys(params) |> collect,
        [dataset_parameters(collection, action, value)
         for value in values(params)])
end

function dataset_parameters(collection::DataCollection, action::Val, param::Vector)
    map(value ->  dataset_parameters(collection, action, value), param)
end

dataset_parameters(::DataCollection, ::Val, value::Any) = value

dataset_parameters(dataset::DataSet, action::Val, params::Any) =
    dataset_parameters(dataset.collection, action, params)

dataset_parameters(adt::AbstractDataTransformer, action::Val, params::Any) =
    dataset_parameters(adt.dataset.collection, action, params)

function dataset_parameters(collection::DataCollection, ::Val{:extract}, param::String)
    dsid_match = match(DATASET_REFERENCE_REGEX, param)
    if !isnothing(dsid_match)
        @advise collection parse(Identifier, dsid_match.captures[1])
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

function Base.get(dataobj::Union{DataSet, DataCollection, <:AbstractDataTransformer},
                  property::AbstractString, default=nothing)
    if haskey(dataobj.parameters, property)
        dataset_parameters(dataobj, Val(:resolve), dataobj.parameters[property])
    else
        default
    end
end

Base.get(dataobj::Union{DataSet, DataCollection, <:AbstractDataTransformer},
         ::typeof(:)) =
    dataset_parameters(dataobj, Val(:resolve), dataobj.parameters)
