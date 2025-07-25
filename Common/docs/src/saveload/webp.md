# [Webp](@id saveload-webp)

Encode and decode WEBP images

# Input/output

The `webp` driver expects data to be provided via `IO`.

It will parse to a `Matrix{<:Colorant}`, and accept such a matrix to save.

# Required packages

  * `WebP`

# Parameters

None

# Usage examples

```toml
[[someimage.loader]]
driver = "webp"
```


