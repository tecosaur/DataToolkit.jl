import REPL.TerminalMenus: request, RadioMenu

"""
    fileextension(storage::DataStorage)

Determine the apropriate file extension for a file caching the contents of
`storage`, "cache" by default.
"""
fileextension(@nospecialize(::DataStorage)) = "cache"

fileextension(s::StoreSource) = s.extension
fileextension(s::CacheSource) = "jls"

"""
    shouldstore(storage::DataStorage)
    shouldstore(loader::DataLoader, T::Type)

Returns `true` if `storage`/`loader` should be stored/cached, `false` otherwise.
"""
shouldstore(@nospecialize(storage::DataStorage)) =
    @getparam(storage."save"::Bool, true) === true

function shouldstore(@nospecialize(loader::DataLoader), T::Type)
    unstorable = T <: IO || T <: Function ||
        QualifiedType(Base.typename(T).wrapper) ==
        QualifiedType(:TranscodingStreams, :TranscodingStream)
    @getparam(loader."cache"::Bool, true) === true && !unstorable
end

"""
    getsource(inventory::Inventory, storage::DataStorage)

Look for the source in `inventory` that backs `storage`,
returning the source or `nothing` if none could be found.
"""
function getsource(inventory::Inventory, @nospecialize(storage::DataStorage))
    recipe = rhash(storage)
    checksum = @getparam storage."checksum"::Union{Bool, String} false
    if checksum === false || checksum == "auto" && haskey(storage.parameters, "lifetime")
        for record in inventory.stores
            if record.recipe == recipe
                return record
            end
        end
    else
        thechecksum = tryparse(Checksum, checksum)
        isnothing(thechecksum) && return
        for record in inventory.stores
            if record.recipe === recipe && record.checksum === thechecksum
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
function getsource(inventory::Inventory, @nospecialize(loader::DataLoader), as::Type)
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
    joinpath(dirname(inventory.file.path), inventory.config.store_dir,
             string(if isnothing(source.checksum)
                        string("R-", string(source.recipe, base=16))
                    else
                        string(source.checksum)
                    end,
                    '.', fileextension(source)))
end

function storefile(inventory::Inventory, source::CacheSource)
    joinpath(dirname(inventory.file.path), inventory.config.cache_dir,
             string("R-", string(source.recipe, base=16),
                    "-T", string(last(first(source.types)), base=16),
                    '-', ifelse(Base.ENDIAN_BOM == 0x04030201, "L", "B"),
                    Sys.WORD_SIZE, '.', fileextension(source)))
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
function storefile(inventory::Inventory, @nospecialize(storage::DataStorage))
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

function storefile(inventory::Inventory, @nospecialize(loader::DataLoader), as::Type)
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
The checksum scheme used when `auto` is specified. Must be recognised by `checksum`.
"""
const CHECKSUM_DEFAULT_SCHEME = :k12

"""
    checksum(file::String, method::Symbol)

Calculate the checksum of `file` with `method`, returning the `Unsigned` result.

Method should be one of:
- `k12`
- `sha512`
- `sha384`
- `sha256`
- `sha224`
- `sha1`
- `md5`
- `crc32c`

Should `method` not be recognised, `nothing` is returned.
"""
function getchecksum(file::String, method::Symbol)
    len, hash = if method === :k12
        @require KangarooTwelve
        res = open(KangarooTwelve.k12, file)::UInt128
        16, reinterpret(UInt8, [hton(res)]) |> collect
    elseif method === :sha512
        @require SHA
        64, open(SHA.sha512, file)::Vector{UInt8}
    elseif method === :sha384
        @require SHA
        48, open(SHA.sha384, file)::Vector{UInt8}
    elseif method === :sha256
        @require SHA
        32, open(SHA.sha256, file)::Vector{UInt8}
    elseif method === :sha224
        @require SHA
        28, open(SHA.sha224, file)::Vector{UInt8}
    elseif method === :sha1
        @require SHA
        20, open(SHA.sha1, file)::Vector{UInt8}
    elseif method === :md5
        @require MD5
        16, collect(open(MD5.md5, file))::Vector{UInt8}
    elseif method === :crc32c
        @require CRC32c
        4, reinterpret(UInt8, [hton(open(CRC32c.crc32c, file)::UInt32)]) |> collect
    else
        return
    end
    Checksum(method, NTuple{len, UInt8}(hash))
end

"""
    getchecksum(storage::DataStorage, file::String)

Returns the `Checksum` for the `file` backing `storage`, or `nothing` if there
is no checksum.

The checksum of `file` is checked against the recorded checksum in `storage`, if
it exists.
"""
function getchecksum(@nospecialize(storage::DataStorage), file::String)
    csumval = @getparam storage."checksum"::Union{Bool, String} false
    csumval == false && return
    csumval == "auto" && haskey(storage.parameters, "lifetime") && return
    if csumval isa String && !occursin(':', csumval) # name of method, or auto
        if !iswritable(storage.dataset.collection)
            @warn "Could not update checksum, data collection is not writable"
            return
        end
        if filesize(file) > CHECKSUM_AUTO_LOG_SIZE || should_log_event("checksum", storage)
            @info "Calculating checksum of $(storage.dataset.name)'s source"
        end
        alg = if csumval == "auto"
            CHECKSUM_DEFAULT_SCHEME
        else Symbol(csumval) end
        checksum = DataToolkitBase.invokepkglatest(getchecksum, file, alg)
        if isnothing(checksum)
            @warn "Checksum scheme '$csumval' is not known, skipping"
            return
        end
        storage.parameters["checksum"] = string(checksum)
        write(storage)
        return checksum
    end
    checksum = tryparse(Checksum, csumval)
    if isnothing(checksum)
        @warn "Checksum value '$checksum' is invalid, ignoring"
        return
    end
    if filesize(file) > CHECKSUM_AUTO_LOG_SIZE || should_log_event("checksum", storage)
        @info "Calculating checksum of $(storage.dataset.name)'s source"
    end
    if checksum.alg === :auto
        checksum = Checksum(CHECKSUM_DEFAULT_SCHEME, checksum.hash)
    end
    actual_checksum = DataToolkitBase.invokepkglatest(getchecksum, file, checksum.alg)
    if isnothing(actual_checksum)
        @warn "Checksum scheme '$(checksum.alg)' is not known, skipping"
        return
    end
    if checksum == actual_checksum
        actual_checksum
    elseif isinteractive() && iswritable(storage.dataset.collection)
        printstyled(" ! ", color=:yellow, bold=true)
        print("Checksum mismatch with $(storage.dataset.name)'s url storage.\n",
                "  Expected the checksum to be $(string(checksum)), got $(string(actual_checksum)).\n",
                "  How would you like to proceed?\n\n")
        options = ["(o) Overwrite checksum to $(string(actual_checksum))", "(a) Abort and throw an error"]
        choice = request(RadioMenu(options, keybindings=['o', 'a']))
        print('\n')
        if choice == 1 # Overwrite
            storage.parameters["checksum"] = string(actual_checksum)
            write(storage)
            actual_checksum
        else
            error(string("Checksum mismatch with $(storage.dataset.name)'s url storage!",
                            " Expected $(string(checksum)), got $(string(actual_checksum))."))
        end
    else
        error(string("Checksum mismatch with $(storage.dataset.name)'s url storage!",
                        " Expected $(string(checksum)), got $(string(actual_checksum))."))
    end
end

"""
    storesave(inventory::Inventory, storage::DataStorage, ::Type{FilePath}, file::FilePath)

Save the `file` representing `storage` into `inventory`.
"""
function storesave(inventory::Inventory, @nospecialize(storage::DataStorage), ::Type{FilePath}, file::FilePath)
    inventory.file.writable || return file
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
    isdir(dirname(dest)) || mkpath(dirname(dest))
    if startswith(file.path, tempdir())
        mv(file.path, dest, force=true)
    else
        cp(file.path, dest, force=true)
    end
    chmod(dest, 0o100444 & filemode(inventory.file.path)) # Make read-only
    update_source!(inventory, newsource, storage.dataset.collection)
    FilePath(dest)
end

"""
    storesave(inventory::Inventory, storage::DataStorage, ::Union{Type{IO}, Type{IOStream}}, from::IO)

Save the IO in `from` representing `storage` into `inventory`.
"""
function storesave(inventory::Inventory, @nospecialize(storage::DataStorage), ::Union{Type{IO}, Type{IOStream}}, from::IO)
    # We could create a tempfile, however there it is near certain that the `storesave`
    # invocation at the end will result in moving the file to the storage dir, which
    # may not be on the same filesystem as the tempdir. In such an event, the file must
    # be copied, which is a needless overhead. We can avoid this eventuality by simply
    # seeing where a similar file to the final `StoreSource` would go according to `inventory`,
    # and create a uniquely named file in the same directory. This ensures that the likely
    # renaming remains just a rename, not a copy.
    newsource = StoreSource(
        rhash(storage),
        [storage.dataset.collection.uuid],
        now(), nothing, fileextension(storage))
    refdest = storefile(inventory, newsource)
    miliseconds = round(Int, 1000 * time())
    partfile = string(refdest, '-', miliseconds, ".part")
    dumpfile = string(refdest, '-', miliseconds, ".dump")
    # In case the user aborts the `write` operation, let's try to clean up
    # the dumpfile. This is just a nice extra, so we'll speculatively use
    # Base internals for now, and revisit this approach if it becomes a problem.
    @static if isdefined(Base.Filesystem, :temp_cleanup_later)
        Base.Filesystem.temp_cleanup_later(partfile)
    end
    write(partfile, from)
    @static if isdefined(Base.Filesystem, :temp_cleanup_forget)
        Base.Filesystem.temp_cleanup_forget(partfile)
    end
    mv(partfile, dumpfile, force=true)
    open(storesave(inventory, storage, FilePath, FilePath(dumpfile)).path, "r")
end

"""
    storesave(inventory::Inventory, storage::DataStorage, as::Type)

Partially apply the first three arguments of `storesave`.
"""
storesave(inventory::Inventory, @nospecialize(storage::DataStorage), as::Type) =
    result -> storesave(inventory, storage, as, result)

"""
    epoch(storage::DataStorage, seconds::Real)

Return the epoch that `seconds` lies in, according to the lifetime
specification of `storage`.
"""
function epoch(@nospecialize(storage::DataStorage), seconds::Real)
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
epoch(@nospecialize(storage::DataStorage)) = epoch(storage, time())

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
    period = Dict("years" => 0.0, "months" => 0.0, "weeks" => 0.0, "days" => 0.0,
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

function pkgtypes!(types::Vector{Type}, seen::Set{UInt}, x::T) where {T}
    if objectid(x) in seen
        return
    else
        push!(seen, objectid(x))
    end
    M = parentmodule(T)
    if M ∉ (Base, Core) && !isnothing(pkgdir(M)) &&
        !startswith(pkgdir(M), Sys.STDLIB) && T ∉ types
        push!(types, T)
    end
    if isconcretetype(T)
        for field in fieldnames(T)
            isdefined(x, field) &&
                pkgtypes!(types, seen, getfield(x, field))
        end
    end
end

function pkgtypes!(types::Vector{Type}, seen::Set{UInt}, x::T) where {T <: AbstractArray}
    if objectid(x) in seen
        return
    else
        push!(seen, objectid(x))
    end
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
            pkgtypes!(types, seen, first(x))
        end
    else
        for index in eachindex(x)
            isassigned(x, index) && pkgtypes!(types, seen, x[index])
        end
    end
end

function pkgtypes!(::Vector{Type}, seen::Set{UInt}, x::Union{Function, Type})
    objectid(x) in seen || push!(seen, objectid(x))
end

function pkgtypes(x)
    types = Type[]
    seen = Set{UInt}()
    pkgtypes!(types, seen, x)
    types
end

"""
    storesave(inventory::Inventory, loader::DataLoader, value::T)

Save the `value` produced by `loader` into `inventory`.
"""
function storesave(inventory::Inventory, @nospecialize(loader::DataLoader), value::T) where {T}
    inventory.file.writable || return value
    ptypes = pkgtypes(value)
    modules = parentmodule.(ptypes)
    for i in eachindex(modules)
        while modules[i] !== parentmodule(modules[i])
            modules[i] = parentmodule(modules[i])
        end
    end
    unique!(modules)
    pkgs = @lock Base.require_lock map(m -> Base.module_keys[m], modules)
    !isempty(ptypes) && first(ptypes) == T ||
        pushfirst!(ptypes, T)
    newsource = CacheSource(
        rhash(loader),
        [loader.dataset.collection.uuid],
        now(), QualifiedType.(ptypes) .=> rhash.(ptypes),
        pkgs)
    dest = storefile(inventory, newsource)
    # Writing directly to `dest` may be the obvious behaviour, but that
    # risks an abort-during-write creating a corrupt file. As such, we
    # first write to a temporary file and then rename it to `dest` once
    # the operation is complete. To ensure that the rename operation does
    # not become a copy, we should avoid using `tempdir` since it may lie
    # on a different filesystem.
    tempdest = string(dest, '-', round(Int, 1000 * time()), ".part")
    isdir(dirname(dest)) || mkpath(dirname(dest))
    isfile(dest) && rm(dest, force=true)
    isfile(tempdest) && rm(tempdest, force=true)
    if should_log_event("cache", loader)
        @info "Saving $T form of $(sprint(show, loader.dataset.name)) to the store"
    end
    Base.invokelatest(serialize, tempdest, value)
    chmod(tempdest, 0o100444 & filemode(inventory.file.path)) # Make read-only
    mv(tempdest, dest, force=true)
    update_source!(inventory, newsource, loader.dataset.collection)
    value
end

"""
    storesave(inventory::Inventory, loader::DataLoader)

Partially apply the first two arguments of `storesave`.
"""
storesave(inventory::Inventory, @nospecialize(loader::DataLoader)) =
    value -> storesave(inventory, loader, value)

"""
    update_source!(inventory::Inventory,
                   source::Union{StoreSource, CacheSource},
                   collection::DataCollection)

Update the record for `source` in `inventory`, based on it having just been used
by `collection`.

This will update the atime of the source, and add `collection` as a reference if
it is not already listed.

Should the `inventory` file not be writable, nothing will be done.
"""
function update_source!(inventory::Inventory,
                        source::Union{StoreSource, CacheSource},
                        collection::DataCollection)
    inventory.file.writable || return
    update_atime(s::StoreSource) =
        StoreSource(s.recipe, s.references, now(), s.checksum, s.extension)
    update_atime(s::CacheSource) =
        CacheSource(s.recipe, s.references, now(), s.types, s.packages)
    inventory = update_inventory!(inventory)
    cinfo = CollectionInfo(collection.uuid, collection.path, collection.name, now())
    # While two collections are only really considered the same if the UUIDs match,
    # if `inventory` exists at a path which a previously known collection existed at,
    # it has doubtless been replaced, and so replacing it is appropriate.
    cindex = findfirst(Base.Fix1((a, b) -> a.uuid == b.uuid || a.path == b.path, collection),
                       inventory.collections)
    if isnothing(cindex)
        push!(inventory.collections, cinfo)
    else
        inventory.collections[cindex] = cinfo
    end
    if collection.uuid ∉ source.references
        push!(source.references, collection.uuid)
    end
    sources = if source isa StoreSource
        inventory.stores
    else
        inventory.caches
    end
    sindex = findfirst(Base.Fix1(≃, source), sources)
    if isnothing(sindex)
        push!(sources, source)
    else
        sources[sindex] = update_atime(source)
    end
    write(inventory)
end
