module PNGFilesExt

using PNGFiles
import DataToolkitCommon: _read_png, _write_png

_read_png(from::IO; kwargs...) =
    PNGFiles.load(from; kwargs...)

_write_png(dest::IO, info; kwargs...) =
    PNGFiles.save(dest, info; kwargs...)

end
