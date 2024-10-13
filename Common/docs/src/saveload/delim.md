# [Delim](@id saveload-delim)

Parse and serialize delimited data

# Input/output

The `delim` driver expects data to be provided via `IO`.

It presents the parsed information as a `Matrix`, and can write `Matrix` and `Vector` types to an `IO`-supporting storage backend.

# Required packages

  * `DelimitedFiles` (the stdlib)

# Parameters

  * `dtype`: The element type of the matrix
  * `delim`: The character used to separate entries
  * `eol`: The character separating each line of input
  * `header`: Whether the first row of data should be read as a header
  * `skipstart`: The number of initial lines of input to ignore
  * `skipblanks`: Whether to ignore blank lines
  * `quotes`: Whether to allow quoted strings to contain column and line delimiters

# Usage examples

```toml
[[iris.loader]]
driver = "delim"
```


