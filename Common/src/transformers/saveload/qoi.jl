function load(loader::DataLoader{:qoi}, from::IO, ::Type{Matrix})
    @import QOI
    QOI.qoi_decode(from)
end

# REVIEW look out for a `QOI.qoi_encode(::IO, info)` method,
# <https://github.com/KristofferC/QOI.jl/issues/11>
function save(writer::DataWriter{:qoi}, dest::FilePath, info::Matrix)
    @import QOI
    QOI.qoi_encode(dest.path, info)
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
