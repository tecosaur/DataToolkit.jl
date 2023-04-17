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

             function create(::Type{DataLoader{$(QuoteNode(name))}}, source::String)
                 if !isnothing(match($(Regex("\\.$ext\$", "i")), source))
                     Dict{String, Any}()
                 end
             end

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
