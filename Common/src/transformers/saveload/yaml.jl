function _read_yaml end # Implemented in `../../../ext/YAMLExt.jl`
function _write_yaml end # Implemented in `../../../ext/YAMLExt.jl`

function load(loader::DataLoader{:yaml}, from::IO, ::Type{T}) where {T <: AbstractDict}
    @require YAML
    invokelatest(_read_yaml, from, T)
end

function save(writer::DataWriter{:yaml}, dest::IO, info::AbstractDict)
    @require YAML
    invokelatest(_write_yaml, dest, info)
end

create(::Type{DataLoader{:yaml}}, source::String) =
    endswith(source, r".ya?ml")

const YAML_DOC = md"""
Parse and serialize YAML data

# Input/output

The `yaml` driver expects data to be provided via `IO`.

It presents the parsed information as a `Dict`, and can write `Dict` types to an
`IO`-supporting storage backend.

# Required packages

- `YAML`

# Parameters

None.

# Usage examples

```toml
[[setup.loader]]
driver = "yaml"
```
"""
