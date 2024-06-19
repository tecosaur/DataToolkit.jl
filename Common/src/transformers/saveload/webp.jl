function _read_webp end # Implemented in `../../../ext/WebPExt.jl`
function _write_webp end # Implemented in `../../../ext/WebPExt.jl`

function load(loader::DataLoader{:webp}, from::IO, ::Type{Matrix})
    @require WebP
    invokelatest(_read_webp, from)
end

function save(writer::DataWriter{:webp}, dest::IO, info::Matrix)
    @require WebP
    invokelatest(_write_webp, dest, info)
end

create(::Type{DataLoader{:webp}}, source::String) =
    !isnothing(match(r"\.webp$"i, source))

create(::Type{DataWriter{:webp}}, source::String) =
    !isnothing(match(r"\.webp$"i, source))

const WEBP_DOC = md"""
Encode and decode WEBP images

# Input/output

The `webp` driver expects data to be provided via `IO`.

It will parse to a `Matrix{<:Colorant}`, and accept such a matrix to save.

# Required packages

- `WebP`

# Parameters

None

# Usage examples

```toml
[[someimage.loader]]
driver = "webp"
```
"""
