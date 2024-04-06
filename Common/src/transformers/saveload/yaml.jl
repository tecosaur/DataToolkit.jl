function load(loader::DataLoader{:yaml}, from::IO, ::Type{T}) where {T <: AbstractDict}
    @import YAML
    dicttype = if !isconcretetype(T)
        Dict{Any, Any}
    else T end
    YAML.load(from; dicttype)
end

function save(writer::DataWriter{:yaml}, dest::IO, info::AbstractDict)
    @import YAML
    YAML.write(dest, info)
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
