module XLSXExt

using XLSX
import DataToolkitCommon: _read_xlsx, _write_xlsx

function _read_xlsx(from::IO, sheet::Union{String, Int}, range::Union{String, Nothing})
    if !isnothing(range)
        XLSX.readdata(from, sheet, range)
    else
        XLSX.readdata(from, sheet)
    end
end

end
