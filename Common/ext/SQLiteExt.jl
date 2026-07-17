module SQLiteExt

using SQLite
using SQLite.DBInterface
import DataToolkitCommon: _read_sqlite, _write_sqlite

_read_sqlite(file::String) = SQLite.DB(file)

_read_sqlite(file::String, query::String) =
    DBInterface.execute(SQLite.DB(file), query)

_write_sqlite(destfile::String, info::Any, name::String; kwargs...) =
    SQLite.load!(info, SQLite.DB(destfile), name; kwargs...)

end
