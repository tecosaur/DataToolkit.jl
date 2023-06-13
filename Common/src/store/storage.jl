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

"""
    getsource(inventory::Inventory, storage::DataStorage)

Look for the source in `inventory` that backs `storage`,
returning the source or `nothing` if none could be found.
"""
function getsource(inventory::Inventory, storage::DataStorage)
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

"""
    getsource(inventory::Inventory, loader::DataLoader, as::Type)

Look for the source in `inventory` that backs the `as` form of `loader`,
returning the source or `nothing` if none could be found.
"""
function getsource(inventory::Inventory, loader::DataLoader, as::Type)
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

"""
    storefile(inventory::Inventory, source::SourceInfo)

Returns the full path for `source` in `inventory`, regardless of whether the
path exists or not.
"""
function storefile(inventory::Inventory, source::StoreSource)
    joinpath(dirname(inventory.file.path),
             string(if isnothing(source.checksum)
                        string("R-", string(source.recipe, base=16))
                    else
                        string(source.checksum[1], '-',
                               string(source.checksum[2], base=16))
                    end,
                    '.', fileextension(source)))
end

function storefile(inventory::Inventory, source::CacheSource)
    joinpath(dirname(inventory.file.path),
             string(string("R-", string(source.recipe, base=16)),
                    '-', string(last(first(source.types)), base=16),
                    '.', fileextension(source)))
end

# For convenient chaning with `getsource`
storefile(::Inventory, ::Nothing) = nothing

"""
    storefile(inventory::Inventory, storage::DataStorage)
    storefile(inventory, loader::DataLoader, as::Type)

Returns a path for the source of `storage`/`loader`, or `nothing` if either the
source or the path does not exist.

Should a source exist, but the file not, the source is removed from `inventory`.
"""
function storefile(inventory::Inventory, storage::DataStorage)
    source = getsource(inventory, storage)
    if !isnothing(source)
        file = storefile(inventory, source)
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

function storefile(inventory::Inventory, loader::DataLoader, as::Type)
    source = getsource(inventory, loader, as)
    if !isnothing(source)
        file = storefile(inventory, source)
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

"""
The file size threshold (in bytes) above which an info message should be printed
when calculating the threshold, no matter what the `checksum` log setting is.

`$(1024^3)` bytes = 1024³ bytes = 1 GiB
"""
const CHECKSUM_AUTO_LOG_SIZE = 1024^3

"""
    getchecksum(storage::DataStorage, file::String)

Returns the checksum tuple for the `file` backing `storage`, or `nothing` if
there is no checksum.

The checksum of `file` is checked against the recorded checksum in `storage`, if
it exists.
"""
function getchecksum(storage::DataStorage, file::String)
    checksum = get(storage, "checksum", false)
    if checksum == "auto"
        if iswritable(storage.dataset.collection)
            if filesize(file) > CHECKSUM_AUTO_LOG_SIZE || should_log_event("checksum", storage)
                @info "Calculating checksum of $(storage.dataset.name)'s source"
            end
            csum = open(io -> crc32c(io), file)
            checksum = string("crc32c:", string(csum, base=16))
            storage.parameters["checksum"] = checksum
            write(storage)
            (:crc32c, csum)
        else
            @warn "Could not update checksum, data collection is not writable"
        end
    elseif checksum !== false
        if filesize(file) > CHECKSUM_AUTO_LOG_SIZE || should_log_event("checksum", storage)
            @info "Calculating checksum of $(storage.dataset.name)'s source"
        end
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

"""
    storesave(inventory::Inventory, storage::DataStorage, ::Type{FilePath}, file::FilePath)

Save the `file` representing `storage` into `inventory`.
"""
function storesave(inventory::Inventory, storage::DataStorage, ::Type{FilePath}, file::FilePath)
    # The checksum must be calculated first because it will likely affect the
    # `rhash` result, should the checksum property be modified and included
    # in the hashing.
    checksum = getchecksum(storage, file.path)
    newsource = StoreSource(
        rhash(storage),
        [storage.dataset.collection.uuid],
        now(), checksum, fileextension(storage))
    dest = storefile(inventory, newsource)
    if should_log_event("store", storage)
        @info "Writing $(sprint(show, storage.dataset.name)) to storage"
    end
    if startswith(file.path, tempdir())
        mv(file.path, dest, force=true)
    else
        cp(file.path, dest, force=true)
    end
    chmod(dest, 0o100444 & filemode(inventory.file.path)) # Make read-only
    update_source!(inventory, newsource, storage.dataset.collection)
    dest
end

"""
    storesave(inventory::Inventory, storage::DataStorage, ::Union{Type{IO}, Type{IOStream}}, from::IO)

Save the IO in `from` representing `storage` into `inventory`.
"""
function storesave(inventory::Inventory, storage::DataStorage, ::Union{Type{IO}, Type{IOStream}}, from::IO)
    dumpfile, dumpio = mktemp()
    write(dumpio, from)
    close(dumpio)
    open(storesave(inventory, storage, FilePath, FilePath(dumpfile)), "r")
end

"""
    storesave(inventory::Inventory, storage::DataStorage, as::Type)

Partially apply the first three arguments of `storesave`.
"""
storesave(inventory::Inventory, storage::DataStorage, as::Type) =
    result -> storesave(inventory, storage, as, result)

"""
    epoch(storage::DataStorage, seconds::Real)

Return the epoch that `seconds` lies in, according to the lifetime
specification of `storage`.
"""
function epoch(storage::DataStorage, seconds::Real)
    if haskey(storage.parameters, "lifetime")
        span = interpret_lifetime(get(storage, "lifetime"))
        offset = get(storage, "lifetime_offset", 0)
        offset_seconds = if offset isa Union{Int, Float64}
            offset
        elseif offset isa String
            interpret_lifetime(offset)
        elseif offset isa Time
            DateTime(Date(1970, 1, 1), offset) |> datetime2unix
        elseif offset isa DateTime
            offset |> datetime2unix
        else
            @warn "Invalid lifetime_offset, ignoring" offset
            0
        end
        (seconds - offset) ÷ span
    end
end

"""
    epoch(storage::DataStorage)

Return the current epoch, according to the lifetime specification of `storage`.
"""
epoch(storage::DataStorage) = epoch(storage, time())

"""
    interpret_lifetime(lifetime::String)

Return the number of seconds in the interval specified by `lifetime`, which is
in one of two formats:

**ISO8061 periods** (with whole numbers only), both forms
1. `P[n]Y[n]M[n]DT[n]H[n]M[n]S`, e.g.
   - `P3Y6M4DT12H30M5S` represents a duration of "3 years, 6 months, 4 days,
     12 hours, 30 minutes, and 5 seconds"
   - `P23DT23H` represents a duration of "23 days, 23 hours"
   - `P4Y` represents a duration of "4 years"
2. `PYYYYMMDDThhmmss` / `P[YYYY]-[MM]-[DD]T[hh]:[mm]:[ss]`, e.g.
   - `P0003-06-04T12:30:05`
   - `P00030604T123005`

**"Prose style" period strings**, which are a repeated pattern of `[number] [unit]`,
where `unit` matches `year|y|month|week|wk|w|day|d|hour|h|minute|min|second|sec|`
optionally followed by an "s", comma, or whitespace. E.g.

- `3 years 6 months 4 days 12 hours 30 minutes 5 seconds`
- `23 days, 23 hours`
- `4d12h`
"""
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
    if M ∉ (Base, Core) && !isnothing(pkgdir(M)) &&
        !startswith(pkgdir(M), Sys.STDLIB) && T ∉ types
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
    if M ∉ (Base, Core) && !isnothing(pkgdir(M)) &&
        !startswith(pkgdir(M), Sys.STDLIB) && T ∉ types
        push!(types, T)
    end
    if isconcretetype(eltype(T))
        if parentmodule(eltype(T)) ∈ (Base, Core)
        elseif isnothing(pkgdir(parentmodule(eltype(T))))
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

"""
    storesave(inventory::Inventory, loader::DataLoader, value::T)

Save the `value` produced by `loader` into `inventory`.
"""
function storesave(inventory::Inventory, loader::DataLoader, value::T) where {T}
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
    dest = storefile(inventory, newsource)
    isfile(dest) && rm(dest, force=true)
    if should_log_event("cache", loader)
        @info "Saving $T form of $(sprint(show, loader.dataset.name)) to the store"
    end
    Base.invokelatest(serialize, dest, value)
    chmod(dest, 0o100444 & filemode(inventory.file.path)) # Make read-only
    update_source!(inventory, newsource, loader.dataset.collection)
    value
end

"""
    storesave(inventory::Inventory, loader::DataLoader)

Partially apply the first two arguments of `storesave`.
"""
storesave(inventory::Inventory, loader::DataLoader) =
    value -> storesave(inventory, loader, value)

"""
    update_source!(inventory::Inventory,
                   source::Union{StoreSource, CacheSource},
                   collection::DataCollection)

Update the record for `source` in `inventory`, based on it having just been used
by `collection`.

This will update the atime of the source, and add `collection` as a reference if
it is not already listed.
"""
function update_source!(inventory::Inventory,
                        source::Union{StoreSource, CacheSource},
                        collection::DataCollection)
    update_atime(s::StoreSource) =
        StoreSource(s.recipe, s.references, now(), s.checksum, s.extension)
    update_atime(s::CacheSource) =
        CacheSource(s.recipe, s.references, now(), s.types, s.packages)
    inventory = update_inventory!(inventory)
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

