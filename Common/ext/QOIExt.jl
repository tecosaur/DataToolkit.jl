module QOIExt

using QOI
import DataToolkitCommon: _read_qoi, _write_qoi

_read_qoi(from::IO) =
    QOI.qoi_decode(from)

_write_qoi(dest::IO, info::Matrix) =
    QOI.qoi_encode(dest, info)

end
