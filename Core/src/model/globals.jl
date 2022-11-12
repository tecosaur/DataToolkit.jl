"""
The `DataCollection.version` set on all created `DataCollection`s, and assumed
when reading any Data.toml files which do not set `data_config_version`.
"""
const LATEST_DATA_CONFIG_VERSION = 0 # while in alpha

"""
The set of data collections currently availible.
"""
const STACK = DataCollection[]

"""
The set of plugins currently availible.
"""
const PLUGINS = Plugin[]

"""
The set of plugins (by name) that should used by default when creating a
new data collection.
"""
const DEFAULT_PLUGINS = String[]

"""
The set of packages loaded by each module via `@addpkg`, for use with `@use`.

More specifically, when a module M invokes `@addpkg pkg id` then
`EXTRA_PACKAGES[M][pkg] = id` is set, and then this information is used
with `@use` to obtain the package from the root module.
"""
const EXTRA_PACKAGES = Dict{Module, Dict{Symbol, Base.PkgId}}()

# For use in construction

"""
The default `priority` field value for instances of `AbstractDataTransformer`.
"""
const DEFAULT_DATATRANSFORMER_PRIORITY = 1

"""
The default `priority` field value for `DataAdvice`s.
"""
const DEFAULT_DATA_ADVISOR_PRIORITY = 1

"""
A tuple of delimitors defining a dataset reference.
For example, if set to `("{", "}")` then `{abc}` would
be recognised as a dataset reference for `abc`.
"""
const DATASET_REFERENCE_WRAPPER = ("📇DATASET<<", ">>")

"""
A regex which matches dataset references.
This is constructed from `DATASET_REFERENCE_WRAPPER`.
"""
const DATASET_REFERENCE_REGEX =
    Regex(string("^", DATASET_REFERENCE_WRAPPER[1],
                 "(.+)", DATASET_REFERENCE_WRAPPER[2],
                 "\$"))

# For plugins / general information

"""
The data specification TOML format constructs a DataCollection, which itself
contains DataSets, comprised of metadata and AbstractDataTransformers.
```
DataCollection
├─ DataSet
│  ├─ AbstractDataTransformer
│  └─ AbstractDataTransformer
├─ DataSet
⋮
```

Within each scope, there are certain reserved attributes. They are listed in
this Dict under the following keys:
- `:collection` for `DataCollection`
- `:dataset` for `DataSet`
- `:transformer` for `AbstractDataTransformer`
"""
const DATA_CONFIG_RESERVED_ATTRIBUTES =
    Dict(:collection => ["data_config_version", "name", "uuid", "plugins", "config"],
         :dataset => ["uuid", "store", "storage", "loader", "writer"],
         :transformer => ["driver", "type", "priority"])

"""
When writing data configuration TOML file, the keys are (recursively) sorted.
Some keys are particularly important though, and so to ensure they are placed
higher a mappings from such keys to a higher sort priority string can be
registered here.

For example, `"config" => "\0x01"` ensures that the special configuration
section is placed before all of the data sets.

This can cause odd behaviour if somebody gives a dataset the same name as a
special key, but frankly that would be a bit silly (given the key names, e.g.
"uuid") and so this is of minimal concern.
"""
const DATA_CONFIG_KEY_SORT_MAPPING =
    Dict("config" => "\0x01",
         "data_config_version" => "\0x01",
         "uuid" => "\0x02",
         "name" => "\0x03",
         "driver" => "\0x03",
         "description" => "\0x04",
         "storage" => "\0x05",
         "loader" => "\0x06",
         "writer" => "\0x07")
