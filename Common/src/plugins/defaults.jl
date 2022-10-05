const DEFAULT_DEFAULTS = Dict{String, Any}()

const DEFAULTS_ALL = "_"

"""
    getdefaults(collection::DataCollection)
    getdefaults(dataset::DataSet)
Get the default parameters of the `dataset`s of a certain data `collection`.
"""
getdefaults(collection::DataCollection) =
    filter((k, v)::Pair -> k ∉ DATA_CONFIG_RESERVED_ATTRIBUTES[:dataset],
           get(collection, "defaults", DEFAULT_DEFAULTS))

getdefaults(dataset::DataSet) = getdefaults(dataset.collection)

"""
    getdefaults(dataset::DataSet, ADT::Type{<:AbstractDataTransformer}, driver::Symbol)
Get the default parameters of an AbstractDataTransformer of type `ADT` using `driver`
attached to a certain `dataset`.
"""
function getdefaults(dataset::DataSet, ADT::Type{<:AbstractDataTransformer}, driver::Symbol)
    adt_type = Dict(:DataStorage => "storage",
                    :DataLoader => "loader",
                    :DataWriter => "writer")[nameof(ADT)]
    # get config.TRANSFORMER.DRIVER values
    transformer_defaults =
        get(get(dataset.collection,
                "defaults", DEFAULT_DEFAULTS),
            adt_type, Dict{String,Any}())
    merge(Dict{String,Any}("priority" => DataToolkitBase.DEFAULT_DATATRANSFORMER_PRIORITY,
                           "support" => string.(supportedtypes(ADT{driver}))),
          get(transformer_defaults, DEFAULTS_ALL, Dict{String,Any}()),
          get(transformer_defaults, String(driver), Dict{String,Any}()))
end

"""
    getdefaults(dataset::DataSet, ADT::Type{<:AbstractDataTransformer}; spec::Dict)
Get the default parameters of an AbstractDataTransformer of type `ADT` where the
transformer driver is read from `ADT` if possible, and taken from `spec` otherwise.
"""
getdefaults(dataset::DataSet, ADT::Type{<:AbstractDataTransformer}; spec::Dict) =
    getdefaults(dataset, ADT, if ADT isa DataType
                    first(ADT.parameters)
                else Symbol(spec["driver"]) end)

"""
    getdefaults(adt::AbstractDataTransformer)
Get the default parameters of `adt`.
"""
getdefaults(adt::AbstractDataTransformer) =
    getdefaults(adt.dataset, typeof(adt), first(typeof(adt).parameters))

"""
    Plugin("defaults", [...])
Applies default values from the "defaults" data collection property.
This works with both DataSets and AbstractDataTransformers.

### Default DataSet property

```toml
[config.defaults]
description="Oh no, nobody bothered to describe this dataset."
```

### Default AbstractDataTransformer property

This is scoped to a particular transformer, and a particular driver. One may
also affect all drivers with the special "all drivers" key `$(DEFAULTS_ALL)`.
Specific-driver defaults always override all-driver defaults.

```toml
[config.defaults.storage.$(DEFAULTS_ALL)]
priority=0

[config.defaults.storage.filesystem]
priority=2
```
"""
const DEFAULTS_PLUGIN = Plugin("defaults", [
    function (post::Function, f::typeof(fromspec), D::Type{DataSet},
              collection::DataCollection, name::String, spec::Dict{String, Any})
        (post, f, (D, collection, name, merge(getdefaults(collection), spec))) end,
    function (post::Function, f::typeof(fromspec), ADT::Type{<:AbstractDataTransformer},
             dataset::DataSet, spec::Dict{String, Any})
        (post, f, (ADT, dataset, merge(getdefaults(dataset, ADT; spec), spec))) end,
    function (post::Function, f::typeof(tospec), ds::DataSet)
        defaults = getdefaults(ds)
        removedefaults(dict) =
            filter(((key, val),) -> !(haskey(defaults, key) && defaults[key] == val),
                   dict)
        (post ∘ removedefaults, f, (ds,))
    end,
    function (post::Function, f::typeof(tospec), adt::AbstractDataTransformer)
        defaults = getdefaults(adt)
        removedefaults(dict) =
            filter(((key, val),) -> !(haskey(defaults, key) && defaults[key] == val),
                   dict)
        (post ∘ removedefaults, f, (adt,))
    end,
])
