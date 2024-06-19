function _read_xlsx end # Implemented in `../../../ext/XLSXExt.jl`
function _write_xlsx end # Implemented in `../../../ext/XLSXExt.jl`

function load(loader::DataLoader{:xlsx}, from::IO, ::Type{Matrix})
    @require XLSX
    sheet = @getparam loader."sheet"::Union{String, Int} 1
    range = @getparam loader."range"::Union{String, Nothing}
    invokelatest(_read_xlsx, from, sheet, range)
end

createpriority(::Type{DataLoader{:xlsx}}) = 10

function create(::Type{DataLoader{:xlsx}}, source::String)
    if !isnothing(match(r"\.xlsx$"i, source))
        ["sheet" => (; prompt="Sheet: ", type=String, default="1"),
         "range" => (; prompt="Range (optional): ", type=String, optional=true)]
    end
end

const XLSX_DOC = md"""
Load Microsoft Excel XML Spreadsheet (XLSX) files

# Input/output

The `xlsx` driver expects data to be provided via a `FilePath`, and will provide
information as a `Matrix`.

# Required packages

- `XLSX`

# Parameters

- `sheet`: the sheet to act on
- `range`: the sheet range that should be loaded

# Usage example

```toml
[[pleaseno]]
driver = "xlsx"
sheet = "better_formats"
range = "A1:A999"
```
"""
