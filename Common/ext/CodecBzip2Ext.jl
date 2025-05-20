module CodecBzip2Ext

using CodecBzip2
import DataToolkitCommon: _read_bzip2, _write_bzip2

_read_bzip2(from::IO, ::Type{IO}) =
    CodecBzip2.Bzip2DecompressorStream(from)

_read_bzip2(from::IO, ::Type{Vector{UInt8}}) =
    transcode(CodecBzip2.Bzip2Decompressor, read(from))

function _write_bzip2(dest::IO, info::IOStream)
    steam = CodecBzip2.Bzip2CompressorStream(dest)
    write(steam, info)
    stream
end

_write_bzip2(dest::IO, info) =
    write(dest, transcode(CodecBzip2.Bzip2Compressor, info))

end
