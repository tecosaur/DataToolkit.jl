function _read_json end # Implemented in `../../../ext/JSON3Ext.jl`
function _write_json end # Implemented in `../../../ext/JSON3Ext.jl`

function load(::DataLoader{:json}, from::IO, ::Type)
    @require JSON3
    invokelatest(_read_json, from)
end

supportedtypes(::Type{DataLoader{:json}}) =
    [QualifiedType(Any)]

function save(writer::DataWriter{:json}, dest::IO, info)
    @require JSON3
    pretty = @getparam writer."pretty"::Bool false
    invokelatest(_write_json, dest, info, pretty)
end

createpriority(::Type{DataLoader{:json}}) = 10

create(::Type{DataLoader{:json}}, source::String) =
    !isnothing(match(r"\.json$"i, source))

const JSON_DOC = md"""
Parse and serialize JSON data

# Input/output

The `json` driver expects data to be provided via `IO`.

It will parse to a number of types depending on the input:
- `JSON3.Object`
- `JSON3.Array`
- `String`
- `Number`
- `Boolean`
- `Nothing`

If you do not wish to impose any expectations on the parsed type, you can ask
for the data of type `Any`.

When writing, any type compatible with `JSON3.write` can be used directly, with
any storage backend supporting `IO`.

# Required packages

- `JSON3`

# Parameters

- `pretty`: Whether to use `JSON3.pretty` when writing

# Usage examples

```toml
[[sample.loader]]
driver = "json"
```
"""
