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

function dataset_parameters(collection::DataCollection, ::Val{:extract}, param::String)
    dsid_match = match(DATASET_REFERENCE_REGEX, param)
    if !isnothing(dsid_match)
        collection.advise(parse, Identifier, dsid_match.captures[1])
    else
        param
    end
end

function dataset_parameters(collection::DataCollection, ::Val{:resolve}, param::Identifier)
    resolve(collection, param)
end

function dataset_parameters(collection::DataCollection, ::Val{:encode}, param::Identifier)
    string(DATASET_REFERENCE_WRAPPER[1],
           collection.advise(string, param),
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
