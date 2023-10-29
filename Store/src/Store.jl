module Store

using DataToolkitBase
using BaseDirs
using CRC32c
using Dates
using Markdown: MD, @md_str
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

include("repl.jl")

"""
    __init__()

Initialise the data store by:
- Registering the plugins `STORE_PLUGIN` and `CACHE_PLUGIN`
- Adding the "store" Data REPL command
- Loading the user inventory
- Registering the GC-on-exit hook
"""
function __init__()
    @dataplugin STORE_PLUGIN :default
    @dataplugin CACHE_PLUGIN
    let pos = searchsorted(REPL_CMDS, STORE_REPL_CMD, by=c -> DataToolkitBase.natkeygen(c.trigger))
        splice!(REPL_CMDS, pos, (STORE_REPL_CMD,))
    end
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
