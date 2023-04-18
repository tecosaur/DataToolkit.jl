module Store

using DataToolkitBase
using BaseDirs
using CRC32c
using Dates
using TOML
using UUIDs
using Serialization

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
    push!(REPL_CMDS, STORE_REPL_CMD)
    update_inventory()
end

end
