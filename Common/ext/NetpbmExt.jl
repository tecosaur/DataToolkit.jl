module NetpbmExt

using Netpbm
import DataToolkitCommon: _read_netpbm, _write_netpbm

_read_netpbm(from::IO) =
    Netpbm.load(from)

_write_netpbm(dest::IO, info::AbstractArray) =
    Netpbm.save(dest, info)

end
