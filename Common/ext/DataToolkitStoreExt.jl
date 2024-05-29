module DataToolkitStoreExt

using DataToolkitCore

using DataToolkitStore: Inventory, StoreSource, getinventory,
    getchecksum, getsource, shouldstore, storefile, update_source!
import DataToolkitStore: rhash, storesave, fileextension

using DataToolkitCommon: dirof
import DataToolkitCommon: is_store_target

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
function storesave(inventory::Inventory, storage::DataStorage{:filesystem}, ::Type{FilePath}, file::FilePath)
    inventory.file.writable || return file
    checksum = getchecksum(storage, file.path)
    newsource = StoreSource(
        rhash(storage),
        [storage.dataset.collection.uuid],
        now(), checksum, last(splitext(file.path))[2:end])
    linkfile = storefile(inventory, newsource)
    isfile(linkfile) && rm(linkfile)
    isdir(dirname(linkfile)) || mkpath(dirname(linkfile))
    symlink(file.path, linkfile)
    update_source!(inventory, newsource, storage.dataset.collection)
    FilePath(linkfile)
end

# Similarly, we need a variant on the generic `storefile` implementation to
# check the symlink and preemptively delete it if the actual file is newer. This
# will now trigger `storesave` again.
function storefile(inventory::Inventory, storage::DataStorage{:filesystem})
    source = getsource(inventory, storage)
    if !isnothing(source)
        linkfile = storefile(inventory, source)
        if isfile(linkfile)
            file = getpath(storage)
            if isfile(file) && lstat(linkfile).ctime > mtime(file)
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

# ------------------
# Passthrough storage
# ------------------

# Ensure that `passthrough` storage registers dependants in the recursive
# hashing interface.
function rhash(storage::DataStorage{:passthrough}, h::UInt)
    ident = @advise storage parse(Identifier, @getparam storage."source"::String)
    sourceh = rhash(storage.dataset.collection, ident, h)
    invoke(rhash, Tuple{AbstractDataTransformer, UInt}, storage, sourceh)
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
