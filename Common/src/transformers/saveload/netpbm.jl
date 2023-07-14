function load(loader::DataLoader{:netpbm}, from::IO, ::Type{AbstractArray})
    @import Netpbm
    Netpbm.load(from)
end

function save(writer::DataWriter{:netpbm}, dest::IO, info::AbstractArray)
    @import Netpbm
    Netpbm.save(dest, info)
end

create(::Type{DataLoader{:netpbm}}, source::String) =
    !isnothing(match(r"\.(?:pbm|pgm|ppm)$"i, source))

create(::Type{DataWriter{:netpbm}}, source::String) =
    !isnothing(match(r"\.(?:pbm|pgm|ppm)$"i, source))

const NETPBM_DOC = md"""
Encode and decode NetPBM files

# Input/output

The `netpbm` driver expects data to be provided via `IO`.

It will parse to a `Matrix{<:Colorant}`.

# Required packages

- `Netpbm`

# Usage examples

```toml
[[someimage.loader]]
driver = "netpbm"
```
"""
