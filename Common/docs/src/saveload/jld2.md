# [JLD2](@id saveload-jld2)

Load and write data in the JLD2 format

# Input/output

The `jld2` driver expects data to be provided via a `FilePath`.

# Required packages

  * `JLD2`

# Parameters

  * `key`: A particular key, or list of keys, to load from the JLD2 dataset.

# Usage examples

```toml
[[sample.loader]]
driver = "jld2"
```


