# [Tiff](@id saveload-tiff)

Encode and decode Tiff files

# Input/output

The `tiff` driver expects data to be provided via `IO`.

It will parse to a `TiffImages.AbstractTIFF`.

# Required packages

  * `TiffImages`

# Usage examples

```toml
[[someimage.loader]]
driver = "tiff"
```


