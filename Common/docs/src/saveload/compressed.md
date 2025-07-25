# [Compressed](@id saveload-compressed)

Load and write a variety of compressed formats

# Description

This is a collection of drivers which enable transparent compression and decompression of data, specifically the following eponymous drivers:

  * `gzip`
  * `zlib`
  * `deflate`
  * `bzip2`
  * `xz`
  * `zstd`

# Input/output

It is assumed that during reading decompression is the desired operation, compression desired when writing.

In both cases, `IO` \to `IO` is the recommended pair of input/output formats, but `IO` or `String` to `Vector{UInt8}` or `String` are also supported.

# Required packages

  * `CodecZlib`, for the following drivers:

      * `gzip`
      * `zlib`
      * `deflate`
  * `CodecBzip2` for the `bzip2` driver
  * `CodecXz` for the `xz` driver
  * `CodecZstd` for the `zstd` driver

# Usage examples

```toml
[[iris-raw.loader]]
driver = "gzip"
```


