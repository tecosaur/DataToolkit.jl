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

# We want to tweak the result of `rhash` to take into account the `mtime` of the
# file if there is no checksum.
function Store.rhash(storage::DataStorage{:filesystem}, h::UInt)
    if @getparam(storage."checksum"::Union{Bool, String}, false) === false
        h = hash(if isfile(@getparam storage."path"::String)
                     mtime(@getparam storage."path"::String)
                 else 0.0 end, h)
    else
        # The checksum should already be accounted for since it's a storage parameter,
        # but that means we should omit the path.
        storage = DataStorage{:filesystem}(
            storage.dataset, storage.type, storage.priority,
            delete!(copy(storage.parameters), "path"))
    end
    invoke(Store.rhash, Tuple{AbstractDataTransformer, UInt}, storage, h)
end

# Variant on the generic `storesave` implementation that copies the file.
# Instead, we create a symlink so we can make use of the checksum metadata.
# We just need to check the symlink is no older than the original file.
function Store.storesave(inventory::Store.Inventory, storage::DataStorage{:filesystem}, ::Type{FilePath}, file::FilePath)
    checksum = Store.getchecksum(storage, file.path)
    newsource = Store.StoreSource(
        Store.rhash(storage),
        [storage.dataset.collection.uuid],
        now(), checksum, last(splitext(file.path))[2:end])
    linkfile = Store.storefile(inventory, newsource)
    isfile(linkfile) && rm(linkfile)
    symlink(file.path, linkfile)
    Store.update_source!(inventory, newsource, storage.dataset.collection)
    linkfile
end

# Similarly, we need a variant on the generic `storefile` implementation to check
# the symlink and pre-emptively delete it if the actual file is newer. This will
# now trigger `storesave` again.
function Store.storefile(inventory::Store.Inventory, storage::DataStorage{:filesystem})
    source = Store.getsource(inventory, storage)
    if !isnothing(source)
        linkfile = Store.storefile(inventory, source)
        if isfile(linkfile)
            file = getpath(storage)
            if isfile(file) && mtime(linkfile) > mtime(file)
                return linkfile
            else
                rm(linkfile)
            end
        end
        # Symlink never existed, or has been removed, so ensure
        # no associated store entry exists.
        index = findfirst(==(source), inventory.stores)
        !isnothing(index) && deleteat!(inventory.stores, index)
        nothing
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
