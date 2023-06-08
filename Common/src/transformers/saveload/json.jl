function load(::DataLoader{:json}, from::IO, as::Type)
    @import JSON3
    JSON3.read(from)
end

supportedtypes(::Type{DataLoader{:json}}) =
    [QualifiedType(Any)]

function save(writer::DataWriter{:json}, dest::IO, info)
    @import JSON3
    if get(writer, "pretty", false)
        JSON3.pretty(dest, info)
    else
        JSON3.write(dest, info)
    end
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
