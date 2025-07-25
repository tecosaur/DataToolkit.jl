# [QOI](@id saveload-qoi)

Encode and decode QOI (Quite Ok Image) files

# Input/output

The `qoi` driver expects data to be provided via `IO`.

It will parse to a `Matrix{<:Colorant}`.

# Required packages

  * `QOI`

# Usage examples

```toml
[[someimage.loader]]
driver = "qoi"
```


