module Store

using DataToolkitBase
using BaseDirs
using Dates
using Markdown
using Serialization
using TOML
using UUIDs

using ..DataToolkitCommon: should_log_event, show_extra, dirof, humansize

const INVENTORY_FILENAME = "Inventory.toml"
USER_STORE::String = ""
USER_INVENTORY::String = ""
function _init_user_inventory!()
    global USER_STORE = if haskey(ENV, "DATATOOLKIT_STORE")
        mkpath(ENV["DATATOOLKIT_STORE"])
    else
        BaseDirs.User.cache(BaseDirs.Project("DataToolkit"), create=true)
    end
    global USER_INVENTORY = joinpath(USER_STORE, INVENTORY_FILENAME)
end

include("types.jl")
include("rhash.jl")
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
    _init_user_inventory!()
    push!(INVENTORIES, load_inventory(USER_INVENTORY))
    atexit() do
        for inv in INVENTORIES
            hours_since = (now() - inv.last_gc).value / (1000 * 60 * 60)
            if inv.config.auto_gc > 0 && hours_since > inv.config.auto_gc
                garbage_collect!(inv; log=false, trimmsg=true)
            end
        end
    end
end

end
