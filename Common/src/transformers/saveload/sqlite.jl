function _read_sqlite end # Implemented in `../../../ext/SQLiteExt.jl`
function _write_sqlite end # Implemented in `../../../ext/SQLiteExt.jl`

function load(loader::DataLoader{:sqlite}, from::FilePath, as::Type)
    @require SQLite
    if QualifiedType(as) == QualifiedType(:SQLite, :DB)
        invokelatest(_read_sqlite, from, as)
    else
        @require DBInterface
        query = @something(@getparam(loader."query"::Union{String, Nothing}),
                           string("SELECT ",
                                  @getparam(loader."columns"::String, "*"),
                                  " FROM ",
                                  @getparam(loader."table"::String, "data")))
        invokelatest(_read_sqlite, from, query, as)
    end
end

supportedtypes(::Type{DataLoader{:sqlite}}) =
    [QualifiedType(:SQLite, :DB),
     QualifiedType(:DataFrames, :DataFrame),
     QualifiedType(:Core, :Any)]

function save(writer::DataWriter{:sqlite}, dest::FilePath, info::Any)
    @require SQLite
    invokelatest(_write_sqlite,
                 info, SQLite.DB(string(dest)), @getparam(writer."table"::String, "data");
                 ifnotexists = @getparam(writer."ifnotexists"::Bool, false),
                 analyze = @getparam(writer."analyze"::Bool, false))
    true
end

createpriority(::Type{DataLoader{:sqlite}}) = 10

function create(::Type{DataLoader{:sqlite}}, source::String)
    if !isnothing(match(r"\.sqlite$"i, source)) &&
        isfile(abspath(dirof(dataset.collection), expanduser(source)))
        ["path" => source,
         "table" => (; prompt="Table: ", type=String,
                     default = "data", optional=true),
         "columns" => (; prompt="Columns: ", type=String,
                       default = "*", optional=true)]
    end
end

const SQLITE_DOC = md"""
Load and write data from/to an SQLite database file

# Input/output

The `sqlite` driver expects to be provided a path to an SQLite database file.

By default this driver announces support for parsing to three data types:
- `SQLite.DB`
- `DataFrame`
- `Any`

Any valid constructor that can be applied to the results of
`DBInterface.execute` will work.

# Required packages

- `SQLite`

# Parameters

### Loader and Writer

- `table`: The table to act on, `data` by default.

### Loader only

- `columns`: columns to select, `*` by default.
- `query`: an SQLite query to run. When provided this overrides the `table` and
  `columns` parameters.

### Writer only

- `ifnotexists`: see the documentation for `SQLite.load!`.
- `analyze`: see the documentation for `SQLite.load!`.

# Usage examples

```toml
[[iris.loader]]
driver = "sqlite"
columns = ["sepal_length", "species"]
```
"""
