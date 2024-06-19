module CodecXzExt

using CodecXz
import DataToolkitCommon: _read_xz, _write_xz

_read_xz(from::IO, ::Type{IO}) =
    CodecXz.XzDecompressorStream(from)

_read_xz(from::IO, ::Type{Vector{UInt8}}) =
    transcode(CodecXz.XzDecompressor, read(from))

function _write_xz(dest::IO, info::IOStream)
    steam = CodecXz.XzCompressorStream(dest)
    write(steam, info)
    stream
end

_write_xz(dest::IO, info) =
    write(dest, transcode(CodecXz.XzCompressor, info))

end
