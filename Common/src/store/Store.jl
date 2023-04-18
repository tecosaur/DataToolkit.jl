module Store

using DataToolkitBase
using BaseDirs
using CRC32c
using Dates
using TOML
using UUIDs

const STORE_DIR = BaseDirs.User.cache(BaseDirs.Project("Data Store"), create=true)

include("types.jl")
include("rhash.jl")
include("inventory.jl")
include("storage.jl")
include("plugin.jl")

include("repl.jl")

function __init__()
    # Cache backends
    @addpkg JLD2 "033835bb-8acc-5ee8-8aae-3f567f8a3819"
    @addpkg JLSO "9da8a3cd-07a3-59c0-a743-3fdc52c30d11"
    @addpkg BSON "fbb218c0-5317-5bc6-957e-2ee96dd4b1f0"
    # Plugins
    @dataplugin STORE_PLUGIN :default
    # Setup
    push!(REPL_CMDS, STORE_REPL_CMD)
    # Initialise inventory
    update_inventory()
end

end
