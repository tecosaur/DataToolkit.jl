function _read_tiff end # Implemented in `../../../ext/TiffImagesExt.jl`
function _write_tiff end # Implemented in `../../../ext/TiffImagesExt.jl`

function load(loader::DataLoader{:tiff}, from::IO, ::Type{AbstractMatrix})
    @require TiffImages
    verbose = @getparam loader."verbose"::Bool false
    lazyio = @getparam loader."lazyio"::Bool false
    mmap = @getparam loader."mmap"::Bool false
    invokelatest(_read_tiff, from; verbose, lazyio, mmap)
end

function save(writer::DataWriter{:tiff}, dest::IO, info::AbstractMatrix)
    @require TiffImages
    invokelatest(_write_tiff, dest, info)
end

createauto(::Type{DataLoader{:tiff}}, source::String) =
    !isnothing(match(r"\.tiff$"i, source))

createauto(::Type{DataWriter{:tiff}}, source::String) =
    !isnothing(match(r"\.tiff$"i, source))

const TIFF_DOC = md"""
Encode and decode Tiff files

# Input/output

The `tiff` driver expects data to be provided via `IOStream`. You can set 
`verbose`, `lazyio`, and `mmap` as described in 
[TiffImages.jl's documentation](https://tamasnagy.com/TiffImages.jl/stable/lib/public/#TiffImages.load).

It will parse to a `TiffImages.AbstractTIFF`.

# Required packages

- `TiffImages`

# Usage examples

```toml
[[someimage.loader]]
driver = "tiff"
verbose = false # default
lazyio = false # default
mmap = false # default
```
"""
