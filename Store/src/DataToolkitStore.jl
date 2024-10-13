module DataToolkitStore

using DataToolkitCore
using BaseDirs
using Dates
using Serialization
using TOML
using UUIDs
using Compat

@compat public load_inventory, fetch!

include("lockfile.jl")
include("types.jl")

const INVENTORY_VERSION = 0

const INVENTORIES = Vector{Inventory}()

const DEFAULT_INVENTORY_CONFIG =
    InventoryConfig(2, 30, 50*1024^3, 1, "store", "cache")
const MSG_LABEL_WIDTH = 10

const INVENTORY_FILENAME = "Inventory.toml"
USER_STORE::String = ""
USER_INVENTORY::String = ""

const PROJECT_SUBPATH = # Handle as const to avoid invalidations (for /some/ reason).
    BaseDirs.projectpath(BaseDirs.Project("DataToolkit"))

const MERKLE_FILENAME = "Merkles.txt"

"""
The checksum scheme used when `auto` is specified. Must be recognised by `checksum`.
"""
const CHECKSUM_DEFAULT_SCHEME = :k12

"""
    STORE_RECORD_ACCESS::Bool

Whether access to stored entries should be updated in the inventory.
This is usually appropriate, but may be worth disabling for collection-wide
checks, as performed by `fetch!` for instance.
"""
STORE_RECORD_ACCESS::Bool = true

function init_user_inventory!()
    global USER_STORE = normpath(if haskey(ENV, "DATATOOLKIT_STORE")
        mkpath(ENV["DATATOOLKIT_STORE"])
    else
        BaseDirs.User.cache(PROJECT_SUBPATH)
    end, "")
    global USER_INVENTORY = joinpath(USER_STORE, INVENTORY_FILENAME)
end

include("rhash.jl")
include("invtoml.jl")
include("merkle.jl")
include("inventory.jl")
include("storage.jl")
include("plugins.jl")

"""
    __init__()

Initialise the data store by:
- Registering the plugins `STORE_PLUGIN` and `CACHE_PLUGIN`
- Loading the user inventory
- Registering the GC-on-exit hook
"""
function __init__()
    # Hashing packages
    @addpkg KangarooTwelve "2a5dabf5-6a39-42aa-818d-ce8a58d1b312"
    @addpkg CRC32c         "8bf52ea8-c179-5cab-976a-9e18b702a9bc"
    @addpkg MD5            "6ac74813-4b46-53a4-afec-0b5dc9d7885c"
    @addpkg SHA            "ea8e919c-243c-51af-8825-aaa63cd721ce"
    # Plugins
    @dataplugin STORE_PLUGIN :default
    @dataplugin CACHE_PLUGIN
    # Inventory loading
    init_user_inventory!()
    push!(INVENTORIES, load_inventory(USER_INVENTORY))
    atexit() do
        for inv in INVENTORIES
            hours_since = (now() - inv.last_gc).value / (1000 * 60 * 60)
            if inv.config.auto_gc > 0 && hours_since > inv.config.auto_gc
                @log_do("store:gc",
                        "Garbage collecting inventory ($(dirname(inv.file.path)))",
                        garbage_collect!(inv; log=false, trimmsg=true))
            end
        end
    end
end

include("precompile.jl")

end
