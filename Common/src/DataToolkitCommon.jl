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
# Defined in `repl/show.jl`, but also wantend for the store plugins.
function show_extra end

include("misc/collectiondir.jl")
include("misc/humansize.jl")
include("store/Store.jl")

include("transformers/storage/filesystem.jl")
include("transformers/storage/null.jl")
include("transformers/storage/passthrough.jl")
include("transformers/storage/git.jl")
include("transformers/storage/raw.jl")
include("transformers/storage/web.jl")

include("transformers/saveload/arrow.jl")
include("transformers/saveload/chain.jl")
include("transformers/saveload/compression.jl")
include("transformers/saveload/csv.jl")
include("transformers/saveload/delim.jl")
include("transformers/saveload/geopackage.jl")
include("transformers/saveload/iotofile.jl")
include("transformers/saveload/jld2.jl")
include("transformers/saveload/jpeg.jl")
include("transformers/saveload/json.jl")
include("transformers/saveload/julia.jl")
include("transformers/saveload/netpbm.jl")
include("transformers/saveload/passthrough.jl")
include("transformers/saveload/png.jl")
include("transformers/saveload/qoi.jl")
include("transformers/saveload/sqlite.jl")
include("transformers/saveload/tar.jl")
include("transformers/saveload/tiff.jl")
include("transformers/saveload/toml.jl")
include("transformers/saveload/xlsx.jl")
include("transformers/saveload/webp.jl")
include("transformers/saveload/yaml.jl")
include("transformers/saveload/zip.jl")

include("plugins/addpkgs.jl")
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
    @addpkg Git_jll        "f8c6e375-362e-5223-8a59-34ff63f689eb"
    # Loaders
    @addpkg ArchGDAL       "c9ce4bd3-c3d5-55b8-8973-c0e20141b8c3"
    @addpkg Arrow          "69666777-d1a9-59fb-9406-91d4454c9d45"
    @addpkg CSV            "336ed68f-0bac-5ca0-87d4-7b16caf5d00b"
    @addpkg CodecBzip2     "523fee87-0ab8-5b00-afb7-3ecf72e48cfd"
    @addpkg CodecXz        "ba30903b-d9e8-5048-a5ec-d1f5b0d4b47b"
    @addpkg CodecZlib      "944b1d66-785c-5afd-91f1-9de20f533193"
    @addpkg CodecZstd      "6b39b394-51ab-5f42-8807-6242bab2b4c2"
    @addpkg ColorTypes     "3da002f7-5984-5a60-b8a6-cbb66c0b333f"
    @addpkg DBInterface    "a10d1c49-ce27-4219-8d33-6db1a4562965"
    @addpkg DelimitedFiles "8bb1440f-4735-579b-a4ab-409b98df4dab"
    @addpkg JLD2           "033835bb-8acc-5ee8-8aae-3f567f8a3819"
    @addpkg JSON3          "0f8b85d8-7281-11e9-16c2-39a750bddbf1"
    @addpkg JpegTurbo      "b835a17e-a41a-41e7-81f0-2f016b05efe0"
    @addpkg Netpbm         "f09324ee-3d7c-5217-9330-fc30815ba969"
    @addpkg PNGFiles       "f57f5aa1-a3ce-4bc8-8ab9-96f992907883"
    @addpkg QOI            "4b34888f-f399-49d4-9bb3-47ed5cae4e65"
    @addpkg SQLite         "0aa819cd-b072-5ff4-a722-6bc24af294d9"
    @addpkg Tar            "a4e569a6-e804-4fa4-b0f3-eef7a1d5b13e"
    @addpkg TiffImages     "731e570b-9d59-4bfa-96dc-6df516fadf69"
    @addpkg TOML           "fa267f1f-6049-4f14-aa54-33bafae1ed76"
    @addpkg WebP           "e3aaa7dc-3e4b-44e0-be63-ffb868ccd7c1"
    @addpkg XLSX           "fdbf4ff8-1666-58a4-91e7-1b58723a45e0"
    @addpkg YAML           "ddb6d928-2868-570f-bddf-ab3f9cf99eb6"
    @addpkg ZipFile        "a5390f91-8eb1-5f08-bee0-b1d1ffed6cea"
    # Plugins
    @addpkg Pkg            "44cfe95a-1eb2-52ea-b672-e2afdf69b78f"

    @dataplugin ADDPKGS_PLUGIN
    @dataplugin DEFAULTS_PLUGIN :default
    @dataplugin LOG_PLUGIN
    @dataplugin VERSIONS_PLUGIN
    @dataplugin MEMORISE_PLUGIN :default

    append!(DataToolkitBase.TRANSFORMER_DOCUMENTATION,
            [(:storage, :filesystem) => FILESYSTEM_DOC,
             (:storage, :git) => GIT_DOC,
             (:storage, :null) => NULL_S_DOC,
             (:storage, :passthrough) => PASSTHROUGH_S_DOC,
             (:storage, :raw) => RAW_DOC,
             (:storage, :web) => WEB_DOC,
             (:loader, :arrow) => ARROW_DOC,
             (:loader, :chain) => CHAIN_DOC,
             (:loader, :gzip) => COMPRESSION_DOC,
             (:loader, :zlib) => COMPRESSION_DOC,
             (:loader, :deflate) => COMPRESSION_DOC,
             (:loader, :bzip2) => COMPRESSION_DOC,
             (:loader, :xz) => COMPRESSION_DOC,
             (:loader, :zstd) => COMPRESSION_DOC,
             (:loader, :csv) => CSV_DOC,
             (:loader, :delim) => DELIM_DOC,
             (:loader, :geopackage) => GEOPACKAGE_DOC,
             (:loader, Symbol("io->file")) => IOTOFILE_DOC,
             (:loader, :jld2) => JLD2_DOC,
             (:loader, :jpeg) => JPEG_DOC,
             (:loader, :json) => JSON_DOC,
             (:loader, :julia) => JULIA_DOC,
             (:loader, :netpbm) => NETPBM_DOC,
             (:loader, :passthrough) => PASSTHROUGH_L_DOC,
             (:loader, :png) => PNG_DOC,
             (:loader, :qoi) => QOI_DOC,
             (:loader, :sqlite) => SQLITE_DOC,
             (:loader, :tar) => TAR_DOC,
             (:loader, :tiff) => TIFF_DOC,
             (:loader, :toml) => TOML_DOC,
             (:loader, :webp) => WEBP_DOC,
             (:loader, :xlsx) => XLSX_DOC,
             (:loader, :yaml) => YAML_DOC,
             (:loader, :zip) => ZIP_DOC,
             (:writer, :gzip) => COMPRESSION_DOC,
             (:writer, :zlib) => COMPRESSION_DOC,
             (:writer, :deflate) => COMPRESSION_DOC,
             (:writer, :bzip2) => COMPRESSION_DOC,
             (:writer, :xz) => COMPRESSION_DOC,
             (:writer, :zstd) => COMPRESSION_DOC,
             (:writer, :csv) => CSV_DOC,
             (:writer, :delim) => DELIM_DOC,
             (:writer, :jpeg) => JPEG_DOC,
             (:writer, :json) => JSON_DOC,
             (:writer, :netpbm) => NETPBM_DOC,
             (:writer, :julia) => JULIA_DOC,
             (:writer, :png) => PNG_DOC,
             (:writer, :qoi) => QOI_DOC,
             (:writer, :sqlite) => SQLITE_DOC,
             (:writer, :tiff) => TIFF_DOC,
             (:writer, :webp) => WEBP_DOC,
             ])
end

include("precompile.jl")

end
