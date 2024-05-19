function _read_qoi end # Implemented in `../../../ext/QOIExt.jl`
function _write_qoi end # Implemented in `../../../ext/QOIExt.jl`

function load(loader::DataLoader{:qoi}, from::IO, ::Type{Matrix})
    @require QOI
    invokelatest(_read_qoi, from)
end

# REVIEW look out for a `QOI.qoi_encode(::IO, info)` method,
# <https://github.com/KristofferC/QOI.jl/issues/11>
function save(writer::DataWriter{:qoi}, dest::FilePath, info::Matrix)
    @require QOI
    invokelatest(_write_qoi, dest, info)
end

create(::Type{DataLoader{:qoi}}, source::String) =
    !isnothing(match(r"\.qoi$"i, source))

create(::Type{DataWriter{:qoi}}, source::String) =
    !isnothing(match(r"\.qoi$"i, source))

const QOI_DOC = md"""
Encode and decode QOI (Quite Ok Image) files

# Input/output

The `qoi` driver expects data to be provided via `IO`.

It will parse to a `Matrix{<:Colorant}`.

# Required packages

- `QOI`

# Usage examples

```toml
[[someimage.loader]]
driver = "qoi"
```
"""
