module DataToolkitCommon

using DataToolkitBase
import DataToolkitBase: load, save, storage,
    getstorage, putstorage, supportedtypes,
    create, createpriority, lint

using PrecompileTools
using Compat

using Tables
using CRC32c: crc32c
using Dates
using Markdown: @md_str
using TOML
using UUIDs

# Defined in `plugins/log.jl`, but also wanted for the store plugins.
function should_log_event end

include("misc/collectiondir.jl")
include("store/Store.jl")

include("transformers/storage/filesystem.jl")
include("transformers/storage/null.jl")
include("transformers/storage/passthrough.jl")
include("transformers/storage/raw.jl")
include("transformers/storage/web.jl")

include("transformers/saveload/chain.jl")
include("transformers/saveload/compression.jl")
include("transformers/saveload/csv.jl")
include("transformers/saveload/delim.jl")
include("transformers/saveload/iotofile.jl")
include("transformers/saveload/jld2.jl")
include("transformers/saveload/json.jl")
include("transformers/saveload/julia.jl")
include("transformers/saveload/passthrough.jl")
include("transformers/saveload/sqlite.jl")
include("transformers/saveload/tar.jl")
include("transformers/saveload/xlsx.jl")
include("transformers/saveload/zip.jl")

include("plugins/defaults.jl")
include("plugins/log.jl") # Must be early so `should_log_event` is availible.
include("plugins/versions.jl")
include("plugins/memorise.jl")

include("repl/REPLcmds.jl")

include("misc/lintrules.jl")

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
    @addpkg Tar            "a4e569a6-e804-4fa4-b0f3-eef7a1d5b13e"
    @addpkg XLSX           "fdbf4ff8-1666-58a4-91e7-1b58723a45e0"
    @addpkg ZipFile        "a5390f91-8eb1-5f08-bee0-b1d1ffed6cea"
    # Plugins
    # JLD2 package, already provided for JLD2 loader.
    @addpkg Pkg            "44cfe95a-1eb2-52ea-b672-e2afdf69b78f"

    @dataplugin DEFAULTS_PLUGIN :default
    @dataplugin LOG_PLUGIN
    @dataplugin VERSIONS_PLUGIN
    @dataplugin MEMORISE_PLUGIN :default

    append!(DataToolkitBase.TRANSFORMER_DOCUMENTATION,
            [(:storage, :filesystem) => FILESYSTEM_DOC,
             (:storage, :null) => NULL_S_DOC,
             (:storage, :passthrough) => PASSTHROUGH_S_DOC,
             (:storage, :raw) => RAW_DOC,
             (:storage, :web) => WEB_DOC,
             (:loader, :chain) => CHAIN_DOC,
             (:loader, :gzip) => COMPRESSION_DOC,
             (:loader, :zlib) => COMPRESSION_DOC,
             (:loader, :deflate) => COMPRESSION_DOC,
             (:loader, :bzip2) => COMPRESSION_DOC,
             (:loader, :xz) => COMPRESSION_DOC,
             (:loader, :zstd) => COMPRESSION_DOC,
             (:loader, :csv) => CSV_DOC,
             (:loader, :delim) => DELIM_DOC,
             (:loader, Symbol("io->file")) => IOTOFILE_DOC,
             (:loader, :jld2) => JLD2_DOC,
             (:loader, :json) => JSON_DOC,
             (:loader, :julia) => JULIA_DOC,
             (:loader, :passthrough) => PASSTHROUGH_L_DOC,
             (:loader, :sqlite) => SQLITE_DOC,
             (:loader, :tar) => TAR_DOC,
             (:loader, :xlsx) => XLSX_DOC,
             (:loader, :zip) => ZIP_DOC,
             (:writer, :gzip) => COMPRESSION_DOC,
             (:writer, :zlib) => COMPRESSION_DOC,
             (:writer, :deflate) => COMPRESSION_DOC,
             (:writer, :bzip2) => COMPRESSION_DOC,
             (:writer, :xz) => COMPRESSION_DOC,
             (:writer, :zstd) => COMPRESSION_DOC,
             (:writer, :csv) => CSV_DOC,
             (:writer, :delim) => DELIM_DOC,
             (:writer, :json) => JSON_DOC,
             (:writer, :julia) => JULIA_DOC,
             (:writer, :sqlite) => SQLITE_DOC,
             ])
end

include("precompile.jl")

end
