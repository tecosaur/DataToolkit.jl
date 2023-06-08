function load(loader::DataLoader{:xlsx}, from::FilePath, as::Type{Matrix})
    @import XLSX
    if !isnothing(get(loader, "range"))
        XLSX.readdata(string(from), get(loader, "sheet", 1), get(loader, "range"))
    else
        XLSX.readdata(string(from), get(loader, "sheet", 1))
    end
end

# When <https://github.com/felipenoris/XLSX.jl/pull/217> is merged,
# we can support IO.

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
