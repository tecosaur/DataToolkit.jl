function getpath(storage::DataStorage{:filesystem})
    spath = @getparam storage."path"::String
    abspath(dirof(storage.dataset.collection), expanduser(spath))
end

function storage(storage::DataStorage{:filesystem}, ::Type{FilePath}; write::Bool)
    path = getpath(storage)
    if @advise storage isfile(path)
        FilePath(path)
    end
end

function storage(storage::DataStorage{:filesystem}, ::Type{DirPath}; write::Bool)
    path = getpath(storage)
    if @advise storage isdir(path)
        DirPath(path)
    end
end

function supportedtypes(::Type{DataStorage{:filesystem}}, params::Dict{String, Any}, dataset::DataSet)
    blind_default = QualifiedType.([IO, Vector{UInt8}, String, FilePath, DirPath])
    !haskey(params, "path") && return blind_default
    path = abspath(dirof(dataset.collection), expanduser(params["path"]))
    if isfile(path)
        QualifiedType.([IO, Vector{UInt8}, String, FilePath])
    elseif isdir(path)
        [QualifiedType(DirPath)]
    else
        blind_default
    end
end

createpriority(::Type{DataStorage{:filesystem}}) = 70

function createauto(::Type{DataStorage{:filesystem}}, source::String, dataset::DataSet)
    if ispath(abspath(dirof(dataset.collection), expanduser(source)))
        Dict("path" => source)
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
