module JpegTurboExt

using JpegTurbo
using ColorTypes: Gray
import DataToolkitCommon: _read_jpeg, _write_jpeg

function _read_jpeg(from::IO, grey::Bool; kwargs...)
    if grey
        JpegTurbo.jpeg_decode(from, Gray; kwargs...)
    else
        JpegTurbo.jpeg_decode(from; kwargs...)
    end
end

_write_jpeg(dest::IO, info::Matrix; kwargs...) =
    JpegTurbo.jpeg_encode(dest, info; kwargs...)

end
