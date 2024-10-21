module DataToolkitStoreExt

using DataToolkitCore
using Dates: now

using DataToolkitStore: Inventory, StoreSource,
    getinventory, getchecksum, getsource, update_source!
import DataToolkitStore: rhash, shouldstore, storesave, storefile, fileextension

using DataToolkitCommon: dirof, getpath
import DataToolkitCommon: is_store_target, approximate_store_dest

is_store_target(storage::DataStorage) = shouldstore(storage)

function approximate_store_dest(storage::DataStorage)
    newsource = StoreSource(
        rhash(storage),
        [storage.dataset.collection.uuid],
        now(), nothing, fileextension(storage))
    inventory = getinventory(storage.dataset.collection)
    refdest = storefile(inventory, newsource)
end

# ------------------
# Non-storable transformers
# ------------------

shouldstore(::DataLoader{:jld2}, ::Type) = false
shouldstore(::DataStorage{:passthrough}) = false
shouldstore(::DataLoader{:passthrough}, ::Type) = false
shouldstore(::DataStorage{:raw}) = false
shouldstore(::DataLoader{:serialization}, ::Type) = false
shouldstore(::DataLoader{:xml}, ::Type) = false

# ------------------
# Filesystem storage
# ------------------

# We want to tweak the result of `rhash` to take into account the `mtime` of the
# file if there is no checksum.
function rhash(storage::DataStorage{:filesystem}, h::UInt)
    if @getparam(storage."checksum"::Union{Bool, String}, false) === false
        path = abspath(dirof(storage.dataset.collection),
                       @getparam storage."path"::String)
        h = hash(if isfile(path) mtime(path) else 0.0 end, h)
    else
        # The checksum should already be accounted for since it's a storage parameter,
        # but that means we should omit the path.
        storage = DataStorage{:filesystem}(
            storage.dataset, storage.type, storage.priority,
            delete!(copy(storage.parameters), "path"))
    end
    invoke(rhash, Tuple{DataStorage, UInt}, storage, h)
end

# Variant on the generic `storesave` implementation that copies the file.
# Instead, we create a symlink so we can make use of the checksum metadata.
# We just need to check the symlink is no older than the original file.
function storesave(inventory::Inventory, storage::DataStorage{:filesystem}, ::Type{T}, path::T) where {T <: SystemPath}
    inventory.file.writable || return path
    checksum = getchecksum(inventory, storage, path)
    ext = if T == DirPath "/" else last(splitext(string(path)))[2:end] end
    newsource = StoreSource(
        rhash(storage),
        [storage.dataset.collection.uuid],
        now(), checksum, ext)
    linkpath = storefile(inventory, newsource)
    ispath(linkpath) && rm(linkpath, force=true, recursive=true)
    isdir(dirname(linkpath)) || mkpath(dirname(linkpath))
    symlink(string(path), linkpath)
    update_source!(inventory, newsource, storage.dataset.collection)
    T(linkpath)
end

# Similarly, we need a variant on the generic `storefile` implementation to
# check the symlink and preemptively delete it if the actual file is newer. This
# will now trigger `storesave` again.
function storefile(inventory::Inventory, storage::DataStorage{:filesystem})
    source = getsource(inventory, storage)
    if !isnothing(source)
        linkpath = storefile(inventory, source)
        if isfile(linkpath)
            file = getpath(storage)
            if isfile(file) && lstat(linkpath).ctime > mtime(file)
                return linkpath
            else
                rm(linkpath)
            end
        elseif isdir(linkpath)
            dir = getpath(storage)
            maxmtime = 0.0
            for (root, dirs, files) in walkdir(dir), file in files
                maxmtime = max(maxmtime, mtime(joinpath(root, file)))
            end
            if isdir(dir) && lstat(linkpath).ctime > maxmtime
                return linkpath
            else
                rm(linkpath)
            end
        end
        # Symlink never existed, or has been removed, so ensure
        # no associated store entry exists.
        index = findfirst(==(source), inventory.stores)
        !isnothing(index) && deleteat!(inventory.stores, index)
        nothing
    end
end

# ------------------
# Passthrough storage
# ------------------

# Ensure that `passthrough` storage registers dependants in the recursive
# hashing interface.
function rhash(storage::DataStorage{:passthrough}, h::UInt)
    ident = @advise storage parse(Identifier, @getparam storage."source"::String)
    sourceh = rhash(storage.dataset.collection, ident, h)
    invoke(rhash, Tuple{DataStorage, UInt}, storage, sourceh)
end

# ------------------
# Web loader
# ------------------

function fileextension(storage::DataStorage{:web})
    m = match(r"\.\w+(?:\.[bgzx]z|\.[bg]?zip|\.zstd)?$",
              @getparam(storage."url"::String))
    if isnothing(m)
        "cache"
    else
        m.match[2:end]
    end
end

# ------------------
# Julia loader
# ------------------

# To account for the contents of a script file.
function rhash(loader::DataLoader{:julia}, h::UInt)
    if haskey(loader.parameters, "path")
        scriptpath =
            abspath(dirof(loader.dataset.collection),
                    expanduser(@getparam loader."pathroot"::String ""),
                    expanduser(@getparam loader."path"::String))
        if isfile(scriptpath)
            h = hash(read(scriptpath), h)
        end
    end
    invoke(rhash, Tuple{DataLoader, UInt}, loader, h)
end


end
