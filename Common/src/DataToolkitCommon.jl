module DataToolkitCommon

using DataToolkitBase
import DataToolkitBase: load, save, storage,
    getstorage, putstorage, supportedtypes,
    create, createpriority

using Compat

using Dates
using Tables
using CRC32c: crc32c
using UUIDs
using TOML

include("storage/filesystem.jl")
include("storage/null.jl")
include("storage/passthrough.jl")
include("storage/raw.jl")
include("storage/web.jl")

include("storage/store/hash.jl")

include("saveload/chain.jl")
include("saveload/compression.jl")
include("saveload/csv.jl")
include("saveload/delim.jl")
include("saveload/iotofile.jl")
include("saveload/jld2.jl")
include("saveload/json.jl")
include("saveload/julia.jl")
include("saveload/passthrough.jl")
include("saveload/sqlite.jl")
include("saveload/xlsx.jl")
include("saveload/zip.jl")

include("plugins/defaults.jl")
include("plugins/log.jl") # Must be early so `should_log_event` is availible.
include("plugins/loadcache.jl")
include("plugins/memorise.jl")

include("repl/repl.jl")

function __init__()
    REPLcmds.add_repl_cmds()

    # Storage
    @addpkg Downloads      "f43a241f-c20a-4ad4-852c-f6b1247861c6"
    @addpkg DelimitedFiles "8bb1440f-4735-579b-a4ab-409b98df4dab"
    @addpkg CSV            "336ed68f-0bac-5ca0-87d4-7b16caf5d00b"
    @addpkg JSON3          "0f8b85d8-7281-11e9-16c2-39a750bddbf1"
    # Loaders
    @addpkg CodecBzip2     "523fee87-0ab8-5b00-afb7-3ecf72e48cfd"
    @addpkg CodecXz        "ba30903b-d9e8-5048-a5ec-d1f5b0d4b47b"
    @addpkg CodecZlib      "944b1d66-785c-5afd-91f1-9de20f533193"
    @addpkg CodecZstd      "6b39b394-51ab-5f42-8807-6242bab2b4c2"
    @addpkg DBInterface    "a10d1c49-ce27-4219-8d33-6db1a4562965"
    @addpkg JLD2           "033835bb-8acc-5ee8-8aae-3f567f8a3819"
    @addpkg SQLite         "0aa819cd-b072-5ff4-a722-6bc24af294d9"
    @addpkg XLSX           "fdbf4ff8-1666-58a4-91e7-1b58723a45e0"
    @addpkg ZipFile        "a5390f91-8eb1-5f08-bee0-b1d1ffed6cea"
    # Plugins
    # JLD2 package, already provided for JLD2 loader.

    @dataplugin DEFAULTS_PLUGIN :default
    @dataplugin LOADCACHE_PLUGIN
    @dataplugin LOG_PLUGIN
    @dataplugin MEMORISE_PLUGIN :default
end

end
