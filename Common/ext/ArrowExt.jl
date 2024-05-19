module ArrowExt

using Arrow
using DataToolkitBase: QualifiedType
import DataToolkitCommon: _read_arrow, _write_arrow

function _read_arrow(io::IO, sink::Type; kwargs...)
    result = Arrow.Table(io; kwargs...) |>
    if sink == Any || sink == Arrow.Table
        identity
    elseif QualifiedType(sink) == QualifiedType(:DataFrames, :DataFrame)
        sink
    end
    result
end

function _write_arrow(io::IO, tbl; kwargs...)
    Arrow.write(io, tbl; kwargs...)
end

end
