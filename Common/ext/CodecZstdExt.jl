module CodecZstdExt

using CodecZstd
import DataToolkitCommon: _read_zstd, _write_zstd

_read_zstd(from::IO, ::Type{IO}) =
    CodecZstd.ZstdDecompressorStream(from)

_read_zstd(from::IO, ::Type{Vector{UInt8}}) =
    transcode(CodecZstd.ZstdDecompressor, read(from))

function _write_zstd(dest::IO, info::IOStream)
    steam = CodecZstd.ZstdCompressorStream(dest)
    write(steam, info)
    stream
end

_write_zstd(dest::IO, info) =
    write(dest, transcode(CodecZstd.ZstdCompressor, info))

end
