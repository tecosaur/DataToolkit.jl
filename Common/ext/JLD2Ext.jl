module JLD2Ext

using JLD2
import DataToolkitCommon: _read_jld2, _write_jld2

_read_jld2(file::String, args...) =
    JLD2.load(file, args...)

_write_jld2(destfile::String, info::Dict{String, Any}) =
    JLD2.save(destfile, info)

end
