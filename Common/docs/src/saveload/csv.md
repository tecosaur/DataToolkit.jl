# [CSV](@id saveload-csv)

Parse and serialize CSV data

While this is the `csv` driver, any format that `CSV.jl` can work with is supported (as this is merely a thin layer around `CSV.jl`)

# Input/output

The `csv` driver expects data to be provided via `IO`.

By default this driver announces support for parsing to three data types:

  * `DataFrame`
  * `Matrix`
  * `CSV.File`

Other `Tables` compatible types are of course supported, and can be used directly (i.e. without having to use the `CSV.File` result) by specifying the type with the `type` transformer keyword.

When writing, any type compatible with `CSV.write` can be used directly, to any storage backend supporting `IO`.

# Required packages

  * `CSV`

# Parameters

  * `args`: keyword arguments to be provided to `CSV.File`, see https://csv.juliadata.org/stable/reading.html#CSV.File.

As a quick-reference, some arguments of particular interest are:

  * `header`: Either,

      * the row number to parse for column names
      * the list of column names
  * `delim`: the column delimiter
  * `types`: a single type, or vector of types to be used for the columns

# Usage examples

```toml
[[iris.loader]]
driver = "csv"

    [iris.loader.args]
    key = value...
```


