function _read_tiff end # Implemented in `../../../ext/TiffImagesExt.jl`
function _write_tiff end # Implemented in `../../../ext/TiffImagesExt.jl`

function load(loader::DataLoader{:tiff}, from::IO, ::Type{AbstractMatrix})
    @require TiffImages
    invokelatest(_read_tiff, from)
end

function save(writer::DataWriter{:tiff}, dest::IO, info::AbstractMatrix)
    @require TiffImages
    invokelatest(_write_tiff, dest, info)
end

create(::Type{DataLoader{:tiff}}, source::String) =
    !isnothing(match(r"\.tiff$"i, source))

create(::Type{DataWriter{:tiff}}, source::String) =
    !isnothing(match(r"\.tiff$"i, source))

const TIFF_DOC = md"""
Encode and decode Tiff files

# Input/output

The `tiff` driver expects data to be provided via `IO`.

It will parse to a `TiffImages.AbstractTIFF`.

# Required packages

- `TiffImages`

# Usage examples

```toml
[[someimage.loader]]
driver = "tiff"
```
"""
