# [PNG](@id saveload-png)

Encode and decode PNG images

# Input/output

The `png` driver expects data to be provided via `IO`.

It will parse to a `Matrix{<:Colorant}`.

# Required packages

  * `PNGFile`

# Parameters

## Reader

  * `gamma`: The gamma correction coefficient.
  * `expand_paletted`: See the PNGFile docs.

## Writer

  * `gamma`: The gamma correction coefficient.
  * `compression_level`: 0-9
  * `compression_strategy`: Either the number or string of: 0/"default", 1/"filtered", 2/"huffman", 3/"rle" (default), or 4/"fixed".
  * `filters`: Either the number or string of: 0/"none", 1/"sub", 3/"average", 4/"paeth" (default)

# Usage examples

```toml
[[someimage.loader]]
driver = "png"
```


