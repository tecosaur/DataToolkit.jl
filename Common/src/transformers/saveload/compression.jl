for (lib, name, ext, stream_decompress, decompress,
     stream_compress, compress) in
    ((:CodecZlib, :gzip, "gzip|gz",
      :GzipDecompressorStream, :GzipDecompressor,
      :GzipCompressorStream, :GzipCompressor),
     (:CodecZlib, :zlib, "zlib",
      :ZlibDecompressorStream, :ZlibDecompressor,
      :ZlibCompressorStream, :ZlibCompressor),
     (:CodecZlib, :deflate, "zz",
      :DeflateDecompressorStream, :DeflateDecompressor,
      :DeflateCompressorStream, :DeflateCompressor),
     (:CodecBzip2, :bzip2, "bzip|bz",
      :Bzip2DecompressorStream, :Bzip2Decompressor,
      :Bzip2CompressorStream, :Bzip2Compressor),
     (:CodecXz, :xz, "xz",
      :XzDecompressorStream, :XzDecompressor,
      :XzCompressorStream, :XzCompressor),
     (:CodecZstd, :zstd, "zstd",
      :ZstdDecompressorStream, :ZstdDecompressor,
      :ZstdCompressorStream, :ZstdCompressor))
    eval(quote
             function load(::DataLoader{$(QuoteNode(name))}, from::IO, ::Type{IO})
                 @import $lib
                 $lib.$stream_decompress(from)
             end

             function load(::DataLoader{$(QuoteNode(name))}, from::IO, ::Type{Vector{UInt8}})
                 @import $lib
                 transcode($lib.$decompress, read(from))
             end

             load(l::DataLoader{$(QuoteNode(name))}, from::IO, ::Type{String}) =
                 String(load(l, from, Vector{UInt8}))

             load(l::DataLoader{$(QuoteNode(name))}, from::String,
                  T::Union{Type{IO}, Type{Vector{UInt8}}, Type{String}}) =
                 load(l, IOBuffer(from), T)

             supportedtypes(::Type{DataLoader{$(QuoteNode(name))}}) =
                 QualifiedType.([IO, Vector{UInt8}, String])

             createpriority(::Type{DataLoader{$(QuoteNode(name))}}) = 10

             create(::Type{DataLoader{$(QuoteNode(name))}}, source::String) =
                 !isnothing(match($(Regex("\\.$ext\$", "i")), source))

             function save(::DataWriter{$(QuoteNode(name))}, dest::IO, info::IOStream)
                 @import $lib
                 stream = $lib.$stream_compress(dest)
                 write(stream, info)
                 stream
             end

             function save(::DataWriter{$(QuoteNode(name))}, dest::IO, info)
                 @import $lib
                 write(dest, transcode($lib.$compress, info))
             end
         end)
end

const COMPRESSION_DOC = md"""
Load and write a variety of compressed formats

# Description

This is a collection of drivers which enable transparent compression and
decompression of data, specifically the following eponymous drivers:
- `gzip`
- `zlib`
- `deflate`
- `bzip2`
- `xz`
- `zstd`

# Input/output

It is assumed that during reading decompression is the desired operation,
compression desired when writing.

In both cases, `IO` \to `IO` is the recommended pair of input/output formats, but
`IO` or `String` to `Vector{UInt8}` or `String` are also supported.

# Required packages

- `CodecZlib`, for the following drivers:
  - `gzip`
  - `zlib`
  - `deflate`
- `CodecBzip2` for the `bzip2` driver
- `CodecXz` for the `xz` driver
- `CodecZstd` for the `zstd` driver

# Usage examples

```toml
[[iris-raw.loader]]
driver = "gzip"
```
"""
