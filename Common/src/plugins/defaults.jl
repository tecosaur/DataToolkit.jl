const DEFAULT_DEFAULTS = Dict{String, Any}()

const DEFAULTS_ALL = "*"

"""
    Plugin("defaults", [...])
Applies default values from the "defaults" data collection property.
This works with both DataSets and AbstractDataTransformers.

### Default DataSet property
```toml
[[data.defaults]]
description="Oh no, nobody bothered to describe this dataset."
```

### Default AbstractDataTransformer property

This is scoped to a particular transformer, and a particular driver. One may
also affect all drivers with the special "all drivers" key `$(DEFAULTS_ALL)`.
Specific-driver defaults always override all-driver defaults.

```toml
[[data.defaults.storage.*]]
priority=0

[[data.defaults.storage.filesystem]]
priority=2
```
"""
const defaults_plugin = Plugin("defaults", [
    function(post::Function, f::typeof(fromspec), D::Type{DataSet},
              collection::DataCollection, name::String, spec::Dict{String, Any})
        defaults = filter((k, v)::Pair -> k ∉ DATA_CONFIG_RESERVED_ATTRIBUTES[:dataset],
                          get(collection, "defaults", DEFAULT_DEFAULTS))
        (post, f, (D, collection, name, merge(defaults, spec)))
    end,
    function(post::Function, f::typeof(fromspec), ADT::Type{<:AbstractDataTransformer},
             dataset::DataSet, spec::Dict{String, Any})
        adt_type = Dict(:DataStorage => "storage",
                        :DataLoader => "loader",
                        :DataWriter => "writer")[nameof(ADT)]
        driver = if ADT isa DataType
            first(ADT.parameters)
        else
            Symbol(spec["driver"])
        end
        # get data.TRANSFORMER.DRIVER values
        transformer_defaults =
            get(get(dataset.collection,
                    "defaults", DEFAULT_DEFAULTS),
                adt_type, Dict{String, Any}())
        defaults_all = merge(
            filter((k, v)::Pair -> k == DEFAULTS_ALL, transformer_defaults)...)
        defaults = merge(
            filter((k, v)::Pair -> k == driver, transformer_defaults)...)
        (post, f, (ADT, dataset, merge(defaults_all, defaults, spec)))
    end
])
