for (lib, name, stream_decompress, decompress,
     stream_compress, compress) in
    ((:CodecZlib, :gzip,
      :GzipDecompressorStream, :GzipDecompressor,
      :GzipCompressorStream, :GzipCompressor),
     (:CodecZlib, :zlib,
      :ZlibDecompressorStream, :ZlibDecompressor,
      :ZlibCompressorStream, :ZlibCompressor),
     (:CodecZlib, :deflate,
      :DeflateDecompressorStream, :DeflateDecompressor,
      :DeflateCompressorStream, :DeflateCompressor),
     (:CodecBzip2, :bzip2,
      :Bzip2DecompressorStream, :Bzip2Decompressor,
      :Bzip2CompressorStream, :Bzip2Compressor),
     (:CodecXz, :xz,
      :XzDecompressorStream, :XzDecompressor,
      :XzCompressorStream, :XzCompressor),
     (:CodecZstd, :zstd,
      :ZstdDecompressorStream, :ZstdDecompressor,
      :ZstdCompressorStream, :ZstdCompressor))
    eval(quote
             function load(::DataLoader{$(QuoteNode(name))}, from::IO, ::Type{IO})
                 @use $lib
                 $lib.$stream_decompress(from)
             end

             function load(::DataLoader{$(QuoteNode(name))}, from::IO, ::Type{Vector{UInt8}})
                 @use $lib
                 transcode($lib.$decompress, read(from))
             end

             load(l::DataLoader{$(QuoteNode(name))}, from::IO, ::Type{String}) =
                 String(load(l, from, Vector{UInt8}))

             load(l::DataLoader{$(QuoteNode(name))}, from::String,
                  T::Union{Type{IO}, Type{Vector{UInt8}}, Type{String}}) =
                 load(l, IOBuffer(from), T)

             supportedtypes(::Type{DataLoader{$(QuoteNode(name))}}) =
                 QualifiedType.([IO, Vector{UInt8}, String])

             function save(::DataWriter{$(QuoteNode(name))}, dest::IO, info::IOStream)
                 @use $lib
                 stream = $lib.$stream_compress(dest)
                 write(stream, info)
                 stream
             end

             function save(::DataWriter{$(QuoteNode(name))}, dest::IO, info)
                 @use $lib
                 write(dest, transcode($lib.$compress, info))
             end
         end)
end
