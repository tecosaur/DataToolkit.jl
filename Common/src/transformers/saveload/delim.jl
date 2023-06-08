function load(loader::DataLoader{:delim}, from::IO, ::Type{Matrix})
    @import DelimitedFiles
    dtype::Type = something(typeify(QualifiedType(get(loader, "type", "Any"))), Any)
    delim::Char = first(get(loader, "delim", ","))
    eol::Char = first(get(loader, "eol", "\n"))
    header::Bool = get(loader, "header", false)
    skipstart::Int = get(loader, "skipstart", 0)
    skipblanks::Bool = get(loader, "skipblanks", false)
    quotes::Bool = get(loader, "quotes", true)
    comment_char::Char = first(get(loader, "comment_char", "#"))
    result = DelimitedFiles.readdlm(
        from, delim, dtype, eol;
        header, skipstart, skipblanks,
        quotes, comment_char)
    close(from)
    result
end

function save(writer::DataWriter{:delim}, dest::IO, info::Union{Vector, Matrix})
    @import DelimitedFiles
    delim::Char = first(get(writer, "delim", ","))
    DelimitedFiles.writedlm(dest, info; delim)
    close(dest)
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

- `type`: The element type of the matrix
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
