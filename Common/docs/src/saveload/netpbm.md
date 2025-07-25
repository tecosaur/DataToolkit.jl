# [Netpbm](@id saveload-netpbm)

Encode and decode NetPBM files

# Input/output

The `netpbm` driver expects data to be provided via `IO`.

It will parse to a `Matrix{<:Colorant}`.

# Required packages

  * `Netpbm`

# Usage examples

```toml
[[someimage.loader]]
driver = "netpbm"
```


