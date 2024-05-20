module WebPExt

using WebP
import DataToolkitCommon: _read_webp, _write_webp

_read_webp(from::IO) =
    WebP.read_webp(from)

_write_webp(dest::IO, info::Matrix) =
    WebP.write_webp(dest, info)

end
