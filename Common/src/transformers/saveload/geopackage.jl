function load(::DataLoader{:geopackage}, from::FilePath, T::Type)
    @import ArchGDAL
    if ArchGDAL.IDataset <: T <: Any
        ArchGDAL.read(string(from))
    end
end

function save(writer::DataWriter{:geopackage}, dest::FilePath, info)
    @import ArchGDAL
    ArchGDAL.write(string(info))
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
