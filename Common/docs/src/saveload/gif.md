# [Gif](@id saveload-gif)

Encode and decode GIF images

# Input/output

The `gif` driver expects data to be provided via `IO`.

It will parse to a `Matrix{<:Colorant}`, and accept such a matrix to save.

# Required packages

  * `GIFImages`

# Parameters

None

# Usage examples

```toml
[[someimage.loader]]
driver = "gif"
```


