module SQLiteQueryExt

using SQLite
using DBInterface
import DataToolkitCommon: _read_sqlite

function _read_sqlite(file::String, ::SQLite.DB, query::String, as::Type)
    db = SQLite.DB(from)
    DBInterface.execute(db, query) |> as
end

end
