import REPL.TerminalMenus: request, RadioMenu

"""
    fileextension(storage::DataStorage)

Determine the apropriate file extension for a file caching the contents of
`storage`, "cache" by default.
"""
fileextension(::DataStorage) = "cache"

"""
    shouldstore(storage::DataStorage)
    shouldstore(loader::DataLoader, T::Type)

Returns `true` if `storage`/`loader` should be stored/cached, `false` otherwise.
"""
shouldstore(::DataStorage) = true

function shouldstore(::DataLoader, T::Type)
    unstorable = T <: IO || T <: Function ||
        QualifiedType(Base.typename(T).wrapper) ==
        QualifiedType(:TranscodingStreams, :TranscodingStream)
    !unstorable
end

function getsource(storage::DataStorage; inventory::Inventory=INVENTORY)
    recipe = rhash(storage)
    checksum = get(storage, "checksum", nothing)
    if isnothing(checksum)
        for record in inventory.sources
            if record.recipe == recipe && isnothing(record.type)
                return record
            end
        end
    elseif checksum == "auto"
        # We don't know what the checksum actually is, and
        # so nothing can match.
    else
        checksum2 = parsechecksum(checksum)
        for record in inventory.sources
            if record.recipe === recipe &&
                record.checksum === checksum2 &&
                isnothing(record.type)
                return record
            end
        end
    end
end

function getsource(loader::DataLoader, as::Type; inventory::Inventory=INVENTORY)
    recipe = rhash(loader)
    for record in inventory.sources
        if record.recipe == recipe && !isnothing(record.type)
            rtype = typeify(first(record.type))
            if !isnothing(rtype) && rtype <: as && rhash(rtype) == last(record.type)
                return record
            end
        end
    end
end

function storefile(source::SourceInfo; inventory::Inventory=INVENTORY)
    joinpath(dirname(inventory.file.path),
             string(if isnothing(source.checksum)
                        string("R-", string(source.recipe, base=16))
                    else
                        string(source.checksum[1], '-',
                               string(source.checksum[2], base=16))
                    end,
                    if isnothing(source.type) ""
                    else '-' * string(last(source.type), base=16) end,
                    '.', source.extension))
end

storefile(::Nothing) = nothing # For convenient chaning with `getsource`

function storefile(storage::DataStorage; inventory::Inventory=INVENTORY)
    source = getsource(storage; inventory)
    if !isnothing(source)
        file = storefile(source; inventory)
        if isfile(file)
            file
        else
            # If the cache file has been removed, remove the associated
            # source info.
            index = findfirst(==(source), inventory.sources)
            !isnothing(index) && deleteat!(inventory.sources, index)
            nothing
        end
    end
end

function storefile(loader::DataLoader, as::Type; inventory::Inventory=INVENTORY)
    source = getsource(loader, as; inventory)
    if !isnothing(source)
        file = storefile(source; inventory)
        if isfile(file)
            file
        else
            # If the cache file has been removed, remove the associated
            # source info.
            index = findfirst(==(source), inventory.sources)
            !isnothing(index) && deleteat!(inventory.sources, index)
            nothing
        end
    end
end

function getchecksum(storage::DataStorage, file::String)
    checksum = get(storage, "checksum", nothing)
    if checksum == "auto"
        if iswritable(storage.dataset.collection)
            @info "Calculating checksum of $(storage.dataset.name)'s source"
            csum = open(io -> crc32c(io), file)
            checksum = string("crc32c:", string(csum, base=16))
            storage.parameters["checksum"] = checksum
            write(storage)
            (:crc32c, csum)
        else
            @warn "Could not update checksum, data collection is not writable"
        end
    elseif !isnothing(checksum)
        @info "Calculating checksum of $(storage.dataset.name)'s source"
        csum = open(io -> crc32c(io), file)
        actual_checksum = string("crc32c:", string(csum, base=16))
        if checksum == actual_checksum
            (:crc32c, csum)
        elseif isinteractive() && iswritable(storage.dataset.collection)
            printstyled(" ! ", color=:yellow, bold=true)
            print("Checksum mismatch with $(storage.dataset.name)'s url storage.\n",
                    "  Expected the CRC32c checksum to be $checksum, got $actual_checksum.\n",
                    "  How would you like to proceed?\n\n")
            options = ["(o) Overwrite checksum to $actual_checksum", "(a) Abort and throw an error"]
            choice = request(RadioMenu(options, keybindings=['o', 'a']))
            print('\n')
            if choice == 1 # Overwrite
                checksum = actual_checksum
                storage.parameters["checksum"] = checksum
                write(storage)
                (:crc32c, csum)
            else
                error(string("Checksum mismatch with $(storage.dataset.name)'s url storage!",
                             " Expected $checksum, got $actual_checksum."))
            end
        else
            error(string("Checksum mismatch with $(storage.dataset.name)'s url storage!",
                         " Expected $checksum, got $actual_checksum."))
        end
    end
end

function storesave(storage::DataStorage, ::Type{FilePath}, file::FilePath)
    # The checksum must be calculated first because it will likely affect the
    # `rhash` result, should the checksum property be modified and included
    # in the hashing.
    checksum = getchecksum(storage, file.path)
    newsource = SourceInfo(
        rhash(storage),
        [storage.dataset.collection.uuid],
        now(),
        checksum,
        nothing,
        fileextension(storage))
    dest = storefile(newsource)
    if startswith(file.path, tempdir())
        mv(file.path, dest)
    else
        cp(file.path, dest)
    end
    chmod(dest, 0o100444 & filemode(STORE_DIR)) # Make read-only
    update_source(newsource, storage)
    dest
end

function storesave(storage::DataStorage, ::Union{Type{IO}, Type{IOStream}}, from::IO)
    dumpfile, dumpio = mktemp()
    write(dumpio, from)
    close(dumpio)
    open(storesave(storage, FilePath, FilePath(dumpfile)), "r")
end

storesave(storage::DataStorage, as::Type) =
    result -> storesave(storage, as, result)

function update_source(source::SourceInfo, storage::DataStorage)
    global INVENTORY
    collection = storage.dataset.collection
    cindex = findfirst(Base.Fix1(≃, collection), INVENTORY.collections)
    sindex = findfirst(Base.Fix1(≃, source), INVENTORY.sources)
    modify_inventory() do
        if isnothing(cindex)
            push!(INVENTORY.collections,
                CollectionInfo(collection.uuid, collection.path,
                                collection.name, now()))
        else
            INVENTORY.collections[cindex] = CollectionInfo(
                collection.uuid, collection.path, collection.name, now())
        end
        if collection.uuid ∉ source.references
            push!(source.references, collection.uuid)
        end
        if isnothing(sindex)
            push!(INVENTORY.sources, source)
        else
            INVENTORY.sources[sindex] = SourceInfo(
                source.recipe, source.references, now(),
                source.checksum, source.extension)
        end
    end
end
