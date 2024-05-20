function _read_gif end # Implemented in `../../../ext/GIFImagesExt.jl`
function _write_gif end # Implemented in `../../../ext/GIFImagesExt.jl`

function load(loader::DataLoader{:gif}, from::FilePath, ::Type{Matrix})
    @require GIFImages
    invokelatest(_read_gif, from.path)
end

function save(writer::DataWriter{:gif}, dest::FilePath, info::Matrix)
    @require GIFImages
    invokelatest(_write_gif, dest.path, info)
end

create(::Type{DataLoader{:gif}}, source::String) =
    !isnothing(match(r"\.gif$"i, source))

create(::Type{DataWriter{:gif}}, source::String) =
    !isnothing(match(r"\.gif$"i, source))

const GIF_DOC = md"""
Encode and decode GIF images

# Input/output

The `gif` driver expects data to be provided via `IO`.

It will parse to a `Matrix{<:Colorant}`, and accept such a matrix to save.

# Required packages

- `GIFImages`

# Parameters

None

# Usage examples

```toml
[[someimage.loader]]
driver = "gif"
```
"""
