function load(loader::DataLoader{:csv}, from::IO, sink::Type)
    @import CSV
    args = @getparam loader."args"::SmallDict{String, Any}
    kwargs = Dict{Symbol, Any}(Symbol(k) => v for (k, v) in args)
    if haskey(kwargs, :types)
        types = kwargs[:types]
        kwargs[:types] = if types isa SmallDict
            Dict{eltype(keys(types)), Type}(
                k => typeify(QualifiedType(v)) for (k, v) in types)
        elseif types isa Vector
            typeify.(QualifiedType.( types))
        elseif types isa String
            typeify(QualifiedType( types))
        else
        end
        if isnothing(kwargs[:types])
            @warn "CSV types argument is invalid: must be a resolvable type string, vector, or dict. Ignoring." types
            delete!(kwargs, :types)
        end
    end
    if haskey(kwargs, :typemap)
        kwargs[:typemap] = Dict{Type, Type}(
            typeify(QualifiedType(k)) => typeify(QualifiedType(v))
            for (k, v) in kwargs[:typemap])
    end
    if haskey(kwargs, :stringtype)
        kwargs[:stringtype] = typeify.(QualifiedType.(kwargs[:stringtype]))
    end
    CSV.File(from; NamedTuple(kwargs)...) |>
        if sink == Any || sink == CSV.File
            identity
        elseif QualifiedType(sink) == QualifiedType(:DataFrames, :DataFrame)
            # Replace `SentinelArray.ChainedVector` columns with standard vectors.
            csv -> let df = sink(csv)
                for (i, col) in enumerate(getfield(df, :columns))
                    getfield(df, :columns)[i] = Array(col)
                end
                df
            end
        elseif sink == Matrix
            Tables.matrix
        else
            sink
        end
end

supportedtypes(::Type{DataLoader{:csv}}) =
    [QualifiedType(:DataFrames, :DataFrame),
     QualifiedType(:CSV, :File),
     QualifiedType(:Base, :Matrix)]

function save(writer::DataWriter{:csv}, dest::IO, info)
    @import CSV
    kwargs = Dict(Symbol(k) => v for (k, v) in
                      @getparam(writer."args"::SmallDict{String, Any}))
    for charkey in (:quotechar, :openquotechar, :escapechar)
        if haskey(kwargs, charkey)
            kwargs[charkey] = first(kwargs[charkey])
        end
    end
    CSV.write(dest, info; NamedTuple(kwargs)...)
end

createpriority(::Type{DataLoader{:csv}}) = 10

create(::Type{DataLoader{:csv}}, source::String) =
    !isnothing(match(r"\.[ct]sv$"i, source))

function lint(loader::DataLoader{:csv}, ::Val{:non_list_csv_args})
    if haskey(loader.parameters, "args") &&
        loader.parameters["args"] isa Vector
        fixer = if length(loader.parameters["args"]) == 1
            function (li::LintItem{DataLoader{:csv}})
                li.source.parameters["args"] =
                    first(li.source.parameters["args"])
                true
            end
        end
        LintItem(loader, :error, :non_list_csv_args,
                 "Argument set is a list of argument sets",
                 fixer, !isnothing(fixer))
    end
end

const CSV_DOC = md"""
Parse and serialize CSV data

While this is the `csv` driver, any format that `CSV.jl` can work with is
supported (as this is merely a thin layer around `CSV.jl`)

# Input/output

The `csv` driver expects data to be provided via `IO`.

By default this driver announces support for parsing to three data types:
- `DataFrame`
- `Matrix`
- `CSV.File`

Other `Tables` compatible types are of course supported, and can be used directly
(i.e. without having to use the `CSV.File` result) by specifying the type with the
`type` transformer keyword.

When writing, any type compatible with `CSV.write` can be used directly, to any
storage backend supporting `IO`.

# Required packages

- `CSV`

# Parameters

- `args`: keyword arguments to be provided to `CSV.File`,
  see https://csv.juliadata.org/stable/reading.html#CSV.File.

As a quick-reference, some arguments of particular interest are:
- `header`: Either,
  - the row number to parse for column names
  - the list of column names
- `delim`: the column delimiter
- `types`: a single type, or vector of types to be used for the columns

# Usage examples

```toml
[[iris.loader]]
driver = "csv"

    [iris.loader.args]
    key = value...
```
"""
