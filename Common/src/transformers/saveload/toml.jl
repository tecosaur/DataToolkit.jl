# `TOML` is already a strong dep

function load(loader::DataLoader{:toml}, from::IO, ::Type{Dict{String, Any}})
    TOML.parse(from)
end

function save(writer::DataWriter{:toml}, dest::IO, info::AbstractDict)
    TOML.print(dest, info, sorted=true)
end

createauto(::Type{DataLoader{:toml}}, source::String) =
    endswith(source, ".toml")

const TOML_DOC = md"""
Parse and serialize TOML data

# Input/output

The `toml` driver expects data to be provided via `IO`.

It presents the parsed information as a `Dict`, and can write `Dict` types to an
`IO`-supporting storage backend.

# Required packages

- `TOML`

# Parameters

None.

# Usage examples

```toml
[[setup.loader]]
driver = "toml"
```
"""
