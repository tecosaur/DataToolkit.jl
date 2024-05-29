module CodecZlibExt

using CodecZlib
import DataToolkitCommon:
    _read_gzip, _write_gzip,
    _read_zlib, _write_zlib,
    _read_deflate, _write_deflate

# Gzip

_read_gzip(from::IO, ::Type{IO}) =
    CodecZlib.GzipDecompressorStream(from)

_read_gzip(from::IO, ::Type{Vector{UInt8}}) =
    transcode(CodecZlib.GzipDecompressor, read(from))

function _write_gzip(dest::IO, info::IOStream)
    steam = CodecZlib.GzipCompressorStream(dest)
    write(steam, info)
    stream
end

_write_gzip(dest::IO, info) =
    write(dest, transcode(CodecZlib.GzipCompressor, info))

# Zlib

_read_zlib(from::IO, ::Type{IO}) =
    CodecZlib.ZlibDecompressorStream(from)

_read_zlib(from::IO, ::Type{Vector{UInt8}}) =
    transcode(CodecZlib.ZlibDecompressor, read(from))

function _write_zlib(dest::IO, info::IOStream)
    steam = CodecZlib.ZlibCompressorStream(dest)
    write(steam, info)
    stream
end

_write_zlib(dest::IO, info) =
    write(dest, transcode(CodecZlib.ZlibCompressor, info))

# Deflate

_read_deflate(from::IO, ::Type{IO}) =
    CodecZlib.DeflateDecompressorStream(from)

_read_deflate(from::IO, ::Type{Vector{UInt8}}) =
    transcode(CodecZlib.DeflateDecompressor, read(from))

function _write_deflate(dest::IO, info::IOStream)
    steam = CodecZlib.DeflateCompressorStream(dest)
    write(steam, info)
    stream
end

_write_deflate(dest::IO, info) =
    write(dest, transcode(CodecZlib.DeflateCompressor, info))

end
