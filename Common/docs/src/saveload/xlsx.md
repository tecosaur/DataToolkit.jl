# [XLSX](@id saveload-xlsx)

Load Microsoft Excel XML Spreadsheet (XLSX) files

# Input/output

The `xlsx` driver expects data to be provided via a `FilePath`, and will provide information as a `Matrix`.

# Required packages

  * `XLSX`

# Parameters

  * `sheet`: the sheet to act on
  * `range`: the sheet range that should be loaded

# Usage example

```toml
[[pleaseno]]
driver = "xlsx"
sheet = "better_formats"
range = "A1:A999"
```


