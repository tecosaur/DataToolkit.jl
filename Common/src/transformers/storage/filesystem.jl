function getpath(storage::DataStorage{:filesystem})
    spath = @getparam storage."path"::String
    abspath(dirof(storage.dataset.collection), expanduser(spath))
end

function storage(storage::DataStorage{:filesystem}, ::Type{IO};
                 write::Bool=false)
    file = getpath(storage)
    if write || isfile(file)
        open(file; write)
    end
end

storage(storage::DataStorage{:filesystem}, ::Type{FilePath}; write::Bool) =
    FilePath(getpath(storage))

function storage(storage::DataStorage{:filesystem}, ::Type{Vector{UInt8}}; write::Bool=false)
    write && error("Cannot represent file as a writable string.")
    read(getpath(storage))
end

function storage(storage::DataStorage{:filesystem}, ::Type{String}; write::Bool=false)
    write && error("Cannot represent file as a writable string.")
    read(getpath(storage), String)
end

supportedtypes(::Type{<:DataStorage{:filesystem, <:Any}}) =
    QualifiedType.([IO, Vector{UInt8}, String, FilePath])

createpriority(::Type{<:DataStorage{:filesystem}}) = 70

function create(::Type{<:DataStorage{:filesystem}}, source::String, dataset::DataSet)
    if isfile(abspath(dirof(dataset.collection), expanduser(source)))
        ["path" => source]
    end
end

const FILESYSTEM_DOC = md"""
Read and write access to local files

# Parameters

- `path`: The path to the file in question, relative to the `Data.toml` if
  applicable, otherwise relative to the current working directory.

# Usage examples

```toml
[[iris.loader]]
driver = "filesystem"
path = "iris.csv"
```

```toml
[[iris.loader]]
driver = "filesystem"
path = "~/data/iris.csv"
```
"""