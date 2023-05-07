module Store

using DataToolkitBase
using BaseDirs
using CRC32c
using Dates
using TOML
using UUIDs
using Serialization

import ..DataToolkitCommon: should_log_event

const STORE_DIR = BaseDirs.User.cache(BaseDirs.Project("Data Store"), create=true)

include("types.jl")
include("rhash.jl")
include("inventory.jl")
include("storage.jl")
include("plugins.jl")

include("repl.jl")

function __init__()
    @dataplugin STORE_PLUGIN :default
    @dataplugin CACHE_PLUGIN
    let pos = searchsorted(REPL_CMDS, STORE_REPL_CMD, by=c -> DataToolkitBase.natkeygen(c.trigger))
        splice!(REPL_CMDS, pos, (STORE_REPL_CMD,))
    end
    update_inventory!()
    atexit() do
        hours_since = (now() - INVENTORY.last_gc).value / (1000 * 60 * 60)
        if INVENTORY.config.auto_gc > 0 && hours_since > INVENTORY.config.auto_gc
            garbage_collect!(; log=false, trimmsg=true)
        end
    end
end

end
