"""
The `DataCollection.version` set on all created `DataCollection`s, and assumed
when reading any Data.toml files which do not set `data_config_version`.
"""
const LATEST_DATA_CONFIG_VERSION = 1

"""
The set of plugins currently availible.
"""
const PLUGINS = Vector{Plugin}()

"""
The set of data collections currently availible.
"""
const COLLECTION_STACK = Dict{Union{String, Nothing}, DataCollection}()

# For use in construction

const DATASET_DEFAULTS = Dict{String, Any}(
    "recency" => -1,
    "store" => "global")

const GLOBAL_STORE = nothing

"""
The default `priority` field value for instances of `AbstractDataTransformer`.
"""
const DEFAULT_DATATRANSFORMER_PRIORITY = 1

"""
The default `priority` field value for `DataTransducer`s.
"""
const DEFAULT_DATATRANSDUCER_PRIORITY = 1

# For use in interpretation

"""
The file path to the global store, which may be used by `DataStore` and
`DataStorage` drivers to substitute `@__GLOBALSTORE__`.
"""
GLOBAL_STORE_PATH = joinpath(first(DEPOT_PATH), "datastore")

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
    Dict(:collection => ["data_config_version", "name", "uuid", "data"],
         :dataset => ["uuid", "store", "storage", "loader", "writer"],
         :transformer => ["driver", "supports", "priority"])
