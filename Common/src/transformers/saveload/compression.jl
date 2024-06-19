for (lib, name, ext) in
    ((:CodecZlib, :gzip, r"\\.(?:gzip|gz)$"i),
     (:CodecZlib, :zlib, r"\\.zlib$"i),
     (:CodecZlib, :deflate, r".zz"i),
     (:CodecBzip2, :bzip2, r"\\.bz(ip)?2?$"i),
     (:CodecXz, :xz, r"\\.xz$"i),
     (:CodecZstd, :zstd, r"\\.zstd$"i))
    eval(quote
             function $(Symbol("_read_$name")) end
             function $(Symbol("_write_$name")) end

             function load(::DataLoader{$(QuoteNode(name))}, from::IO, T::Type{IO})
                 @require $lib
                 invokelatest($(Symbol("_read_$name")), from, T)
             end

             function load(::DataLoader{$(QuoteNode(name))}, from::IO, T::Type{Vector{UInt8}})
                 @require $lib
                 invokelatest($(Symbol("_read_$name")), from, T)
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
                 !isnothing(match($ext, source))

             function save(::DataWriter{$(QuoteNode(name))}, dest::IO, info)
                 @require $lib
                 invokelatest($(Symbol("_write_$name")), dest, info)
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
