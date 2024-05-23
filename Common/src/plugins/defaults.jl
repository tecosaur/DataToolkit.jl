const DEFAULT_DEFAULTS = Dict{String, Any}()

"""
    DEFAULTS_ALL

The special key that applies to all drivers of a particular `AbstractDataTransformer`.
"""
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
    getdefaults(dataset::DataSet, ADT::Type{<:AbstractDataTransformer},
               driver::Symbol; resolvetype::Bool=true)

Get the default parameters of an AbstractDataTransformer of type `ADT` using
`driver` attached to a certain `dataset`. The default type resolved when
`resolvetype` is set.
"""
function getdefaults(dataset::DataSet, ADT::Type{<:AbstractDataTransformer},
                     driver::Symbol, spec::Dict{String, Any};
                     resolvetype::Bool=true)
    adt_type = Dict(:DataStorage => "storage",
                    :DataLoader => "loader",
                    :DataWriter => "writer")[nameof(ADT)]
    concrete_adt = if isconcretetype(ADT) ADT else ADT{driver} end
    # get config.TRANSFORMER.DRIVER values
    transformer_defaults =
        get(get(dataset.collection,
                "defaults", DEFAULT_DEFAULTS),
            adt_type, Dict{String,Any}())
    implicit_defaults = Dict{String, Any}(
        "priority" => DataToolkitBase.DEFAULT_DATATRANSFORMER_PRIORITY)
    if resolvetype
        types = string.(supportedtypes(concrete_adt, spec, dataset))
        implicit_defaults["type"] =
            if length(types) == 1 first(types) else types end
    end
    merge(implicit_defaults,
          get(transformer_defaults, DEFAULTS_ALL, Dict{String,Any}()),
          get(transformer_defaults, String(driver), Dict{String,Any}()))
end

"""
    getdefaults(dataset::DataSet, ADT::Type{<:AbstractDataTransformer};
                spec::Dict, resolvetype::Bool=true)

Get the default parameters of an AbstractDataTransformer of type `ADT` where the
transformer driver is read from `ADT` if possible, and taken from `spec`
otherwise. The default type resolved when `resolvetype` is set.
"""
getdefaults(dataset::DataSet, ADT::Type{<:AbstractDataTransformer};
            spec::Dict, resolvetype::Bool=true) =
                getdefaults(dataset, ADT,
                            if ADT isa DataType
                                first(ADT.parameters)
                            else Symbol(get(spec, "driver", "MISSING")) end,
                            spec; resolvetype)

"""
    getdefaults(adt::AbstractDataTransformer)

Get the default parameters of `adt`.
"""
getdefaults(adt::AbstractDataTransformer) =
    getdefaults(adt.dataset, typeof(adt), first(typeof(adt).parameters), adt.parameters)

"""
    defaults_read_ds_a( <fromspec(::Type{DataSet}, collection::DataCollection, name::String, spec::Dict{String, Any})> )

Advice that merges default values into `spec`, while parsing a `DataSet`.

Part of `DEFAULTS_PLUGIN`.
"""
function defaults_read_ds_a(
    f::typeof(fromspec), D::Type{DataSet}, collection::DataCollection, name::String, spec::Dict{String, Any})
    (f, (D, collection, name, merge(getdefaults(collection), spec)))
end

"""
    defaults_read_adt_a( <fromspec(::Type{AbstractDataTransformer}, dataset::DataSet, spec::Dict{String, Any})> )

Advice that merges default values into `spec`, while parsing an `AbstractDataTransformer`.

Part of `DEFAULTS_PLUGIN`.
"""
function defaults_read_adt_a(
    f::typeof(fromspec), ADT::Type{<:AbstractDataTransformer}, dataset::DataSet, spec::Dict{String, Any})
    (f, (ADT, dataset,
         merge(getdefaults(dataset, ADT; spec, resolvetype=false),
               spec)))
end

"""
    defaults_write_ds_a( <tospec(::Type{DataSet}, ds::DataSet)> )

Advice that removes default values from `spec`, just before writing a `DataSet`.

Part of `DEFAULTS_PLUGIN`.
"""
function defaults_write_ds_a(f::typeof(tospec), ds::DataSet)
    defaults = getdefaults(ds)
    removedefaults(dict) =
        filter(((key, val),) -> !(haskey(defaults, key) && defaults[key] == val),
               dict)
    (removedefaults, f, (ds,))
end

"""
    defaults_write_adt_a( <tospec(::Type{AbstractDataTransformer}, adt::AbstractDataTransformer)> )

Advice that removes default values from `spec`, just before writing an `AbstractDataTransformer`.

Part of `DEFAULTS_PLUGIN`.
"""
function defaults_write_adt_a(f::typeof(tospec), adt::AbstractDataTransformer)
    defaults = getdefaults(adt)
    removedefaults(dict) =
        filter(((key, val),) -> !(haskey(defaults, key) && defaults[key] == val),
               dict)
    (removedefaults, f, (adt,))
end

"""
Apply default values from the "defaults" data collection property.
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
const DEFAULTS_PLUGIN =
    Plugin("defaults", [
        defaults_read_ds_a,
        defaults_read_adt_a,
        defaults_write_ds_a,
        defaults_write_adt_a])
