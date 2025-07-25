module XLSXExt

using XLSX
import DataToolkitCommon: _read_xlsx, _write_xlsx

function _read_xlsx(from::IO, ::Type{Matrix{Any}}, sheet::Union{String, Int}, range::Union{String, Nothing})
    if !isnothing(range)
        XLSX.readdata(from, sheet, range, infer_eltypes=true)
    else
        XLSX.readdata(from, sheet, infer_eltypes=true)
    end
end

function _read_xlsx(from::IO, astype::Type, sheet::Union{String, Int}, range::Union{String, Nothing})
    table = if !isnothing(range)
        XLSX.readtable(from, sheet, range, infer_eltypes=true)
    else
        XLSX.readtable(from, sheet, infer_eltypes=true)
    end
    if astype == XLSX.DataTable
        table
    else
        astype(table)
    end
end

end
