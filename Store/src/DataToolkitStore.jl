module DataToolkitStore

using DataToolkitCore
using BaseDirs
using Dates
using Serialization
using TOML
using UUIDs

@static if VERSION >= v"1.11"
    eval(Expr(:public, :load_inventory, :fetch!))
end

include("lockfiles.jl")
using .LockFiles

include("types.jl")

const INVENTORY_VERSION = 0

"All registered inventories."
const INVENTORIES = Inventory[]

const DEFAULT_INVENTORY_CONFIG =
    InventoryConfig(2, 30, 50*1024^3, 1, "store", "cache")
const MSG_LABEL_WIDTH = 10

const INVENTORY_FILENAME = "Inventory.toml"
USER_STORE::String = ""
USER_INVENTORY::String = ""

const PROJECT_SUBPATH = # Handle as const to avoid invalidations (for /some/ reason).
    BaseDirs.applicationpath(BaseDirs.App("DataToolkit"))

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

"""
    isprecompiling() -> Bool

Whether this process is generating output (precompiling), in which case the
store is never garbage collected automatically.
"""
# TODO: Replace `jl_generating_output` with `Base.generating_output` once min Julia >= 1.11
isprecompiling() = ccall(:jl_generating_output, Cint, ()) == 1

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
- Locating the user store
- Registering the flush-on-exit and GC-on-exit hooks

Inventories are loaded when first used, so only those are collected at exit.
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
    init_user_inventory!()
    # Registered before the GC hook so (LIFO) it flushes any writes GC queues.
    atexit(flushpendingwrites)
    isprecompiling() || atexit(autogc)
end

"""
    autogc()

Garbage collect each registered inventory whose last collection is older than
its `auto_gc` interval (in hours).
"""
function autogc()
    for inv in INVENTORIES
        hours_since = (now() - inv.last_gc).value / (1000 * 60 * 60)
        if inv.config.auto_gc > 0 && hours_since > inv.config.auto_gc
            @log_do("store:gc",
                    "Garbage collecting inventory ($(dirname(inv.file.path)))",
                    garbage_collect!(inv; log=false, trimmsg=true))
        end
    end
end

include("precompile.jl")

end
