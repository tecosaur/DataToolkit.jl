function load(loader::DataLoader{:tiff}, from::IO, ::Type{AbstractArray})
    @import TiffImages
    TiffImages.load(from)
end

function save(writer::DataWriter{:tiff}, dest::IO, info::AbstractArray)
    @import TiffImages
    TiffImages.save(dest, info)
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
