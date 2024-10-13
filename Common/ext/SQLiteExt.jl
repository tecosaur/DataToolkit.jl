module SQLiteExt

using SQLite
import DataToolkitCommon: _read_sqlite, _write_sqlite

_read_sqlite(file::String, ::SQLite.DB) =
    SQLite.DB(from)

_write_sqlite(destfile::String, info::Any, name::String; kwargs...) =
    SQLite.load!(info, SQLite.DB(destfile), name; kwargs...)

end
