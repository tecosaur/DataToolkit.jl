# [Jpeg](@id saveload-jpeg)

Encode and decode JPEG images

# Input/output

The `jpeg` driver expects data to be provided via `IO`.

It will parse to a `Matrix{<:Colorant}`.

# Required packages

  * `JpegTurbo`

# Parameters

## Reader

  * `transpose`: Whether to permute the image's width and height dimension
  * `scale_ratio`: scale the image this ratio in `M/8` with `M ∈ 1:16` (values will be mapped to the closest value)
  * `grayscale`: Whether to process the image in grayscale

## Writer

  * `transpose`: Whether to permute the image's width and height dimension
  * `quality`: The IJG-scale JPEG quality value, between 0 and 100.

# Usage examples

```toml
[[someimage.loader]]
driver = "jpeg"
```


