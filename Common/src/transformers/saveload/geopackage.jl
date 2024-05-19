function _read_geopkg end # Implemented in `../../../ext/ArchGDALExt.jl`
function _write_geopkg end # Implemented in `../../../ext/ArchGDALExt.jl`

function load(::DataLoader{:geopackage}, from::FilePath, T::Type)
    @require ArchGDAL
    invokelatest(_read_geopkg, from.path, T)
end

function save(writer::DataWriter{:geopackage}, dest::FilePath, info)
    @require ArchGDAL
    invokelatest(_write_geopkg, dest.path, info)
end

supportedtypes(::Type{DataLoader{:geopackage}}) =
    [QualifiedType(:ArchGDAL, :IDataset), QualifiedType(:Core, :Any)]

createpriority(::Type{DataLoader{:geopackage}}) = 10

create(::Type{DataLoader{:geopackage}}, source::String) =
    !isnothing(match(r"\.gpkg$"i, source))

const GEOPACKAGE_DOC = md"""
Parse and serialize .gpkg files

# Input/output

The `geopackage` driver expects data to be provided via `FilePath`.

# Required packages

+ `ArchGDAL`

# Parameters

Additional arguments for the writer and loader are not currently supported.

# Usage examples

```toml
[[sample.loader]]
driver = "geopackage"
```
"""
