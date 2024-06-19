module CSVExt

using CSV
import DataToolkitCommon: _read_csv, _write_csv

_read_csv(from::IO; kwargs...) =
    CSV.File(from; kwargs...)

_write_csv(dest::IO, info; kwargs...) =
    CSV.write(dest, info; kwargs...)

end
