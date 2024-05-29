function _read_dlm end # Implemented in `../../../ext/DelimitedFilesExt.jl`
function _write_dlm end # Implemented in `../../../ext/DelimitedFilesExt.jl`

function load(loader::DataLoader{:delim}, from::IO, ::Type{Matrix})
    @require DelimitedFiles
    dtype::Type = something(typeify(QualifiedType(@getparam loader."type"::String "Any")), Any)
    delim::Char = first(@getparam loader."delim"::String ",")
    eol::Char = first(@getparam loader."eol"::String "\n")
    header::Bool = @getparam loader."header"::Bool false
    skipstart::Int = @getparam loader."skipstart"::Int 0
    skipblanks::Bool = @getparam loader."skipblanks"::Bool false
    quotes::Bool = @getparam loader."quotes"::Bool true
    comment_char::Char = first(@getparam loader."comment_char"::String "#")
    invokelatest(_read_dlm, from, delim, dtype, eol;
                 header, skipstart, skipblanks, quotes, comment_char)
end

function save(writer::DataWriter{:delim}, dest::IO, info::Union{Vector, Matrix})
    @require DelimitedFiles
    delim::Char = first(@getparam writer."delim"::String ",")
    invokelatest(_write_dlm, dest, info; delim)
end

const DELIM_DOC = md"""
Parse and serialize delimited data

# Input/output

The `delim` driver expects data to be provided via `IO`.

It presents the parsed information as a `Matrix`, and can write `Matrix` and `Vector`
types to an `IO`-supporting storage backend.

# Required packages

+ `DelimitedFiles` (the stdlib)

# Parameters

- `dtype`: The element type of the matrix
- `delim`: The character used to separate entries
- `eol`: The character separating each line of input
- `header`: Whether the first row of data should be read as a header
- `skipstart`: The number of initial lines of input to ignore
- `skipblanks`: Whether to ignore blank lines
- `quotes`: Whether to allow quoted strings to contain column and line delimiters

# Usage examples

```toml
[[iris.loader]]
driver = "delim"
```
"""
