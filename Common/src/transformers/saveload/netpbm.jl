function _read_netpbm end # Implemented in `../../../ext/NetpbmExt.jl`
function _write_netpbm end # Implemented in `../../../ext/NetpbmExt.jl`

function load(loader::DataLoader{:netpbm}, from::IO, ::Type{AbstractArray})
    @require Netpbm
    invokelatest(_read_netpbm, from)
end

function save(writer::DataWriter{:netpbm}, dest::IO, info::AbstractArray)
    @require Netpbm
    invokelatest(_write_netpbm, dest, info)
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
