function _read_arrow end # Implemented in `../../../ext/ArrowExt.jl`
function _write_arrow end # Implemented in `../../../ext/ArrowExt.jl`

function load(loader::DataLoader{:arrow}, io::IO, sink::Type)
    @require Arrow
    convert = @getparam loader."convert"::Bool true
    invokelatest(_read_arrow, io, sink; convert)
end

function save(writer::DataWriter{:arrow}, io::IO, tbl)
    @require Arrow
    compress         = @getparam writer."compress"::Union{Symbol, Nothing} nothing
    alignment        = @getparam writer."alignment"::Int 8
    dictencode       = @getparam writer."dictencode"::Bool false
    dictencodenested = @getparam writer."dictencodenested"::Bool false
    denseunions      = @getparam writer."denseunions"::Bool true
    largelists       = @getparam writer."largelists"::Bool false
    maxdepth         = @getparam writer."maxdepth"::Int 6
    ntasks           = @getparam writer."ntasks"::Int Int(typemax(Int32))
    invokelatest(_write_arrow, io, tbl;
                 compress, alignment,
                 dictencode, dictencodenested,
                 denseunions, largelists,
                 maxdepth, ntasks)
end

supportedtypes(::Type{DataLoader{:arrow}}) =
    [QualifiedType(:DataFrames, :DataFrame),
     QualifiedType(:Arrow, :Table)]

create(::Type{DataLoader{:arrow}}, source::String) =
    !isnothing(match(r"\.arrow$"i, source))

createpriority(::Type{DataLoader{:arrow}}) = 10

const ARROW_DOC = md"""
Parse and serialize arrow files

# Input/output

The `arrow` driver expects data to be provided via `IO`.

By default this driver supports parsing to two data types:
- `DataFrame`
- `Arrow.Table`

# Required packages

+ `Arrow`

# Parameters

- `convert`: controls whether certain arrow primitive types will be converted to more friendly Julia defaults
- The writer mirrors the arguments available in `Arrow.write`.

# Usage examples

```toml
[[iris.loader]]
driver = "arrow"
```
"""
