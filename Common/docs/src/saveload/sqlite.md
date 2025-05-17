# [Sqlite](@id saveload-sqlite)

Load and write data from/to an SQLite database file

# Input/output

The `sqlite` driver expects to be provided a path to an SQLite database file.

By default this driver announces support for parsing to three data types:

  * `SQLite.DB`
  * `DataFrame`
  * `Any`

Any valid constructor that can be applied to the results of `DBInterface.execute` will work.

# Required packages

  * `SQLite`

# Parameters

### Loader and Writer

  * `table`: The table to act on, `data` by default.

### Loader only

  * `columns`: columns to select, `*` by default.
  * `query`: an SQLite query to run. When provided this overrides the `table` and `columns` parameters.

### Writer only

  * `ifnotexists`: see the documentation for `SQLite.load!`.
  * `analyze`: see the documentation for `SQLite.load!`.

# Usage examples

```toml
[[iris.loader]]
driver = "sqlite"
columns = ["sepal_length", "species"]
```


