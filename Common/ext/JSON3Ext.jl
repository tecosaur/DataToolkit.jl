module JSON3Ext

using JSON3
import DataToolkitCommon: _read_json, _write_json

_read_json(from::IO) =
    JSON3.read(from)

_write_json(dest::IO, info, pretty::Bool) =
    (if pretty JSON3.pretty else JSON3.write end)(dest, info)

end
