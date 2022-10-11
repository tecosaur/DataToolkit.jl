function load(loader::DataLoader{:sqlite}, from::FilePath, as::Type)
    @use SQLite
    db = SQLite.DB(string(from))
    # We would dispatch on `as` being a `SQLite.DB`,
    # but we only just made `SQLite` availible so this
    # decision needs to be made within the function body.
    if as == SQLite.DB
        db
    else
        @use DBInterface
        query = @something(get(loader, "query"),
                           string("SELECT ",
                                  get(loader, "columns", "*"),
                                  " FROM ",
                                  get(loader, "table", "data")))
        DBInterface.execute(db, query) |> as
    end
end

function save(writer::DataWriter{:sqlite}, dest::FilePath, info::Any)
    @use SQLite
    SQLite.load!(info, SQLite.DB(string(dest)), get(writer, "table", "data");
                 ifnotexists = get(writer, "ifnotexists", false),
                 analyze = get(writer, "analyze", false))
    true
end
