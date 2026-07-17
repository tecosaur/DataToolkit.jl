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

# `readtable` takes a column range ("B:D") positionally and the starting row as
# a keyword, unlike `readdata`'s cell range, so a "B2:D10" range must be split.
function _read_xlsx(from::IO, astype::Type, sheet::Union{String, Int}, range::Union{String, Nothing})
    columns, first_row = nothing, nothing
    if !isnothing(range)
        if count(==(':'), range) == 1
            start, _ = eachsplit(range, ':')
            columns = filter(!isdigit, range)
            first_row = if any(isdigit, start) parse(Int, filter(isdigit, start)) end
        else
            @warn "Range $range is improperly formatted, ignoring. The range should give a pair of columns or cells, like 'B:D' or 'A10:C20'."
        end
    end
    table = if isnothing(columns)
        XLSX.readtable(from, sheet; first_row, infer_eltypes=true)
    else
        XLSX.readtable(from, sheet, columns; first_row, infer_eltypes=true)
    end
    if astype == XLSX.DataTable
        table
    else
        astype(table)
    end
end

end
