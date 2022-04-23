const FILESYSTEM_PATH_REPLACEMENTS =
    Dict(r"^@__DIR__" => function (storage)
             something(storage.dataset.collection.path, pwd())
         end
         )

# TODO @__DIR__ substitutions, etc.
function storage(storage::DataStorage{:filesystem}, ::Type{IO};
                 write::Bool=false)
    file = get(storage, "path")
    open(file; write)
end
