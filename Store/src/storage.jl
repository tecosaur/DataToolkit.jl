import REPL.TerminalMenus: request, RadioMenu

"""
    fileextension(storage::DataStorage)

Determine the apropriate file extension for a file caching the contents of
`storage`, "cache" by default.
"""
fileextension(::DataStorage) = "cache"

fileextension(s::StoreSource) = s.extension
fileextension(s::CacheSource) = "jls"

"""
    shouldstore(storage::DataStorage)
    shouldstore(loader::DataLoader, T::Type)

Returns `true` if `storage`/`loader` should be stored/cached, `false` otherwise.
"""
shouldstore(storage::DataStorage) = get(storage, "save", true) === true

function shouldstore(loader::DataLoader, T::Type)
    unstorable = T <: IO || T <: Function ||
        QualifiedType(Base.typename(T).wrapper) ==
        QualifiedType(:TranscodingStreams, :TranscodingStream)
    get(loader, "cache", true) === true && !unstorable
end

function getsource(storage::DataStorage; inventory::Inventory=INVENTORY)
    recipe = rhash(storage)
    checksum = get(storage, "checksum", false)
    if checksum === false
        for record in inventory.stores
            if record.recipe == recipe
                return record
            end
        end
    elseif checksum == "auto"
        # We don't know what the checksum actually is, and
        # so nothing can match.
    else
        checksum2 = parsechecksum(checksum)
        for record in inventory.stores
            if record.recipe === recipe && record.checksum === checksum2
                return record
            end
        end
    end
end

function getsource(loader::DataLoader, as::Type; inventory::Inventory=INVENTORY)
    recipe = rhash(loader)
    for record in inventory.caches
        if record.recipe == recipe
            type, thash = first(record.types)
            rtype = typeify(type)
            if !isnothing(rtype) && rtype <: as && rhash(rtype) == thash
                return record
            end
        end
    end
end

function storefile(source::StoreSource; inventory::Inventory=INVENTORY)
    joinpath(dirname(inventory.file.path),
             string(if isnothing(source.checksum)
                        string("R-", string(source.recipe, base=16))
                    else
                        string(source.checksum[1], '-',
                               string(source.checksum[2], base=16))
                    end,
                    '.', fileextension(source)))
end

function storefile(source::SourceInfo; inventory::Inventory=INVENTORY)
    joinpath(dirname(inventory.file.path),
             string(string("R-", string(source.recipe, base=16)),
                    '-', string(last(first(source.types)), base=16),
                    '.', fileextension(source)))
end

storefile(::Nothing) = nothing # For convenient chaning with `getsource`

function storefile(storage::DataStorage; inventory::Inventory=INVENTORY)
    source = getsource(storage; inventory)
    if !isnothing(source)
        file = storefile(source; inventory)
        if isfile(file)
            file
        else
            @info "Deleting store"
            # If the cache file has been removed, remove the associated
            # source info.
            index = findfirst(==(source), inventory.stores)
            !isnothing(index) && deleteat!(inventory.stores, index)
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
            index = findfirst(==(source), inventory.caches)
            !isnothing(index) && deleteat!(inventory.caches, index)
            nothing
        end
    end
end

function getchecksum(storage::DataStorage, file::String)
    checksum = get(storage, "checksum", false)
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
    elseif checksum !== false
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
    newsource = StoreSource(
        rhash(storage),
        [storage.dataset.collection.uuid],
        now(), checksum, fileextension(storage))
    dest = storefile(newsource)
    if should_log_event("store", storage)
        @info "Writing $(sprint(show, storage.dataset.name)) to storage"
    end
    if startswith(file.path, tempdir())
        mv(file.path, dest, force=true)
    else
        cp(file.path, dest, force=true)
    end
    chmod(dest, 0o100444 & filemode(STORE_DIR)) # Make read-only
    update_source!(newsource, storage)
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


function interpret_lifetime(lifetime::String)
    period = SmallDict("years" => 0.0, "months" => 0.0, "weeks" => 0.0, "days" => 0.0,
                       "hours" => 0.0, "minutes" => 0.0, "seconds" => 0.0)
    iso8061_duration_1 = r"^P(?:(?P<years>\d+)Y)?(?:(?P<months>\d+)M)?(?:(?P<days>\d+)D)?(?:T(?:(?P<hours>\d+)H)?(?:(?P<minutes>\d+)M)?(?:(?P<seconds>\d+)S)?)?$"
    iso8061_duration_2 = r"^P(?P<years>\d\d\d\d)-?(?P<months>\d\d)-?(?P<days>\d\d)(?:T(?P<hours>\d\d):?(?P<minutes>\d\d)?:?(?P<seconds>\d\d)?)?$"
    iso_period = @something(match(iso8061_duration_1, lifetime),
                            match(iso8061_duration_2, lifetime),
                            Some(nothing))
    if !isnothing(iso_period)
        for unit in keys(iso_period)
            if !isnothing(iso_period[unit])
                period[unit] = parse(Int, iso_period[unit]) |> Float64
            end
        end
    else
        humanperiod = r"(?P<quantity>\d+(?:\.\d*)?)\s*(?P<unit>year|y|month|week|wk|w|day|d|hour|h|minute|min|second|sec|)s?,?\s*"i
        unitmap = Dict("year" => "years", "y" => "years",
                       "month" => "months",
                       "week" => "weeks", "wk" => "weeks", "w" => "weeks",
                       "day" => "days", "d" => "days",
                       "hour" => "hours", "h" => "hours",
                       "minute" => "minutes", "min" => "minutes",
                       "second" => "seconds", "sec" => "seconds", "" => "seconds")
        while (m = match(humanperiod, lifetime)) |> !isnothing
            period[unitmap[m["unit"]]] = parse(Float64, m["quantity"])
            lifetime = string(lifetime[1:m.match.offset],
                              lifetime[m.match.ncodeunits+1:end])
        end
        if !isempty(lifetime)
            @warn "Unmatched content in period string: $(sprint(show, lifetime))"
        end
    end
    period["years"] * 365.2422 * 24 * 60 * 60 +
        period["months"] * 30.437 * 24 * 60 * 60 +
        period["weeks"] * 7 * 24 * 60 * 60 +
        period["days"] * 24 * 60 * 60 +
        period["hours"] * 60 * 60 +
        period["minutes"] * 60 +
        period["seconds"]
end

function pkgtypes!(types::Vector{Type}, x::T) where {T}
    M = parentmodule(T)
    if M ∉ (Base, Core) && !startswith(pkgdir(M), Sys.STDLIB) && T ∉ types
        push!(types, T)
    end
    if isconcretetype(T)
        for field in fieldnames(T)
            pkgtypes!(types, getfield(x, field))
        end
    end
end

function pkgtypes!(types::Vector{Type}, x::T) where {T <: AbstractArray}
    M = parentmodule(T)
    if M ∉ (Base, Core) && !startswith(pkgdir(M), Sys.STDLIB) && T ∉ types
        push!(types, T)
    end
    if isconcretetype(eltype(T))
        if parentmodule(eltype(T)) ∈ (Base, Core)
        elseif startswith(pkgdir(parentmodule(eltype(T))), Sys.STDLIB)
        elseif eltype(T) ∈ types
        elseif !isempty(x) && isassigned(x, firstindex(x))
            pkgtypes!(types, first(x))
        end
    else
        for elt in x
            pkgtypes!(types, elt)
        end
    end
end

function pkgtypes(x)
    types = Type[]
    pkgtypes!(types, x)
    types
end

function storesave(loader::DataLoader, value::T) where {T}
    ptypes = pkgtypes(value)
    modules = unique(parentmodule.(ptypes))
    pkgs = @lock Base.require_lock map(m -> Base.module_keys[m], modules)
    !isempty(ptypes) && first(ptypes) == T ||
        pushfirst!(ptypes, T)
    newsource = CacheSource(
        rhash(loader),
        [loader.dataset.collection.uuid],
        now(), QualifiedType.(ptypes) .=> rhash.(ptypes),
        pkgs)
    dest = storefile(newsource)
    if should_log_event("cache", loader)
        @info "Saving $T form of $(sprint(show, loader.dataset.name)) to the store"
    end
    Base.invokelatest(serialize, dest, value)
    chmod(dest, 0o100444 & filemode(STORE_DIR)) # Make read-only
    update_source!(newsource, loader)
    value
end

storesave(loader::DataLoader) =
    value -> storesave(loader, value)

function update_source!(source::Union{StoreSource, CacheSource},
                        transformer::AbstractDataTransformer;
                        inventory::Inventory=INVENTORY)
    inventory === INVENTORY && update_inventory!()
    collection = transformer.dataset.collection
    cindex = findfirst(Base.Fix1(≃, collection), inventory.collections)
    sources = if source isa StoreSource
        inventory.stores
    else
        inventory.caches
    end
    sindex = findfirst(Base.Fix1(≃, source), sources)
    if isnothing(cindex)
        push!(inventory.collections,
                CollectionInfo(collection.uuid, collection.path,
                                collection.name, now()))
    else
        inventory.collections[cindex] = CollectionInfo(
            collection.uuid, collection.path, collection.name, now())
    end
    if collection.uuid ∉ source.references
        push!(source.references, collection.uuid)
    end
    if isnothing(sindex)
        push!(sources, source)
    else
        sources[sindex] = update_atime(source)
    end
    write(inventory)
end

update_atime(s::StoreSource) =
    StoreSource(s.recipe, s.references, now(), s.checksum, s.extension)

update_atime(s::CacheSource) =
    CacheSource(s.recipe, s.references, now(), s.types, s.packages)
