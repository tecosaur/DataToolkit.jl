"""
The `DataCollection.version` set on all created `DataCollection`s, and assumed
when reading any Data.toml files which do not set `data_config_version`.
"""
const LATEST_DATA_CONFIG_VERSION = 1

const PLUGINS = Dict{String, Any}()

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
