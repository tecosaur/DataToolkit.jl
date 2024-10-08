"""
    fileextension(storage::DataStorage)

Determine the appropriate file extension for a file caching the contents of
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
            if record.recipe === recipe && record.checksum == thechecksum
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
    basename = if isnothing(source.checksum)
        string("R-", string(source.recipe, base=16))
    else
        string(source.checksum)
    end
    ext = fileextension(source)
    joinpath(dirname(inventory.file.path), inventory.config.store_dir,
             if ext == "/" # dir
                 basename
             else
                 string(basename, '.', ext)
             end)
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
    checksum(algorithm::Symbol, data::Union{<:IO, Vector{UInt8}, String})

Calculate the checksum of `data` with `algorithm`, returning the `Checksum` result.

This function can be curried with the method `checksum(algorithm::Symbol)`.

The specified algorithm should be one of:
- `auto` (alias of `$CHECKSUM_DEFAULT_SCHEME`)
- `k12`
- `sha512`
- `sha384`
- `sha256`
- `sha224`
- `sha1`
- `md5`
- `crc32c`

Should `algorithm` not be recognised, `nothing` is returned.
"""
function checksum end

function checksum(algorithm::Symbol, data::Union{<:IO, Vector{UInt8}, String})
    func = checksum(algorithm)
    isnothing(func) && return
    func(data)::Checksum
end

function checksum(algorithm::Symbol)
    invokepkglatest(_checksum, algorithm)::Union{Function, Nothing}
end

function _checksum(algorithm::Symbol)
    algorithm === :auto && return _checksum(CHECKSUM_DEFAULT_SCHEME, data)
    hash = if algorithm === :k12
        @require KangarooTwelve
        let k12 = KangarooTwelve.k12
            data -> Checksum(algorithm, reinterpret(
                UInt8, [hton(invokelatest(k12, data)::UInt128)]) |> collect)
        end
    elseif algorithm === :sha512
        @require SHA
        let sha512 = SHA.sha512
            data -> Checksum(algorithm, invokelatest(sha512, data)::Vector{UInt8})
        end
    elseif algorithm === :sha384
        @require SHA
        let sha384 = SHA.sha384
            data -> Checksum(algorithm, invokelatest(sha384, data)::Vector{UInt8})
        end
    elseif algorithm === :sha256
        @require SHA
        let sha256 = SHA.sha256
            data -> Checksum(algorithm, invokelatest(sha256, data)::Vector{UInt8})
        end
    elseif algorithm === :sha224
        @require SHA
        let sha224 = SHA.sha224
            data -> Checksum(algorithm, invokelatest(sha224, data)::Vector{UInt8})
        end
    elseif algorithm === :sha1
        @require SHA
        let sha1 = SHA.sha1
            data -> Checksum(algorithm, invokelatest(sha1, data)::Vector{UInt8})
        end
    elseif algorithm === :md5
        @require MD5
        let md5 = MD5.md5
            data -> Checksum(algorithm, invokelatest(md5, data)::Vector{UInt8})
        end
    elseif algorithm === :crc32c
        @require CRC32c
        let crc32c = CRC32c.crc32c
            data -> Checksum(algorithm, reinterpret(
                UInt8, [hton(invokelatest(crc32c, data)::UInt32)]) |> collect)
        end
    end
end

struct ChecksumMismatch <: Exception
    target::String
    expected::Checksum
    actual::Checksum
end

function Base.showerror(io::IO, e::ChecksumMismatch)
    println(io, "Expected $target checksum $(string(e.expected)), got $(string(e.actual))")
end

function checksumalgorithm(@nospecialize(storage::DataStorage))
    csumval = @getparam storage."checksum"::Union{Bool, String} false
    csumval == false && return
    csumval == "auto" &&
        return if !haskey(storage.parameters, "lifetime")
            CHECKSUM_DEFAULT_SCHEME end
    schecksum = tryparse(Checksum, csumval)
    if !isnothing(schecksum)
        schecksum.alg
    elseif csumval isa String && !occursin(':', csumval)
        Symbol(csumval)
    end
end

"""
    getchecksum(inventory::Inventory, storage::DataStorage, path::Union{FilePath, DirPath})

Returns the `Checksum` for the `path` backing `storage`, or `nothing` if there
is no checksum.

The checksum of `path` is checked against the recorded checksum in `storage`, if
it exists.
"""
function getchecksum(inventory::Inventory, @nospecialize(storage::DataStorage), path::Union{FilePath, DirPath})
    alg = checksumalgorithm(storage)
    isnothing(alg) && return
    if !ispath(string(path))
        @warn "Path $(path) does not exist"
        return
    end
    csumval = @getparam storage."checksum"::Union{Bool, String} false
    if csumval isa String && !occursin(':', csumval) # name of method, or auto
        if !iswritable(storage.dataset.collection)
            @warn "Could not update checksum, data collection is not writable"
            return
        end
        schecksum = @log_do(
            "store:checksum",
            "Calculating checksum of $(storage.dataset.name)'s source",
            if path isa FilePath
                open(checksum(alg), path.path)
            else # path isa DirPath
                mtree = merkle(inventory.merkles, path.path, alg)
                isnothing(mtree) && return
                mtree.checksum
            end)
        if isnothing(schecksum)
            @warn "Checksum scheme '$csumval' is not known, skipping"
            return
        end
        storage.parameters["checksum"] = string(schecksum)
        write(storage)
        return schecksum
    end
    schecksum = tryparse(Checksum, csumval)
    if isnothing(schecksum)
        @warn "Checksum value '$schecksum' is invalid, ignoring"
        return
    end
    if schecksum.alg === :auto
        schecksum = Checksum(CHECKSUM_DEFAULT_SCHEME, schecksum.hash)
    end
    actual_checksum = @log_do(
        "store:checksum",
        "Calculating checksum of $(storage.dataset.name)'s source",
        if path isa FilePath
            open(checksum(alg), path.path)
        else # path isa DirPath
            mtree = merkle(inventory.merkles, path.path, alg;
                           last_checksum = schecksum)
            isnothing(mtree) && return
            mtree.checksum
        end)
    if isnothing(actual_checksum)
        @warn "Checksum scheme '$(alg)' is not known, skipping"
        return
    end
    if schecksum == actual_checksum
        actual_checksum
    elseif isinteractive() && iswritable(storage.dataset.collection)
        if hasmethod(should_overwrite, Tuple{String, String, String}) &&
            should_overwrite(storage.dataset.name, string(schecksum), string(actual_checksum))
            storage.parameters["checksum"] = string(actual_checksum)
            write(storage)
            actual_checksum
        else
            throw(ChecksumMismatch(storage.dataset.name, schecksum, actual_checksum))
        end
    else
        throw(ChecksumMismatch(storage.dataset.name, schecksum, actual_checksum))
    end
end

function should_overwrite end # Implemented in `../../ext/StorageREPL.jl`

"""
    storesave(inventory::Inventory, storage::DataStorage, ::Type{typeof(path)}, path::SystemPath)

Save the `path` representing `storage` into `inventory`.
"""
function storesave(inventory::Inventory, @nospecialize(storage::DataStorage), ::Type{T}, path::T) where {T <: SystemPath}
    inventory.file.writable || return path
    # The checksum must be calculated first because it will likely affect the
    # `rhash` result, should the checksum property be modified and included
    # in the hashing.
    checksum = getchecksum(inventory, storage, path)
    ext = if T == DirPath "/" else fileextension(storage) end
    newsource = StoreSource(
        rhash(storage),
        [storage.dataset.collection.uuid],
        now(), checksum, ext)
    dest = storefile(inventory, newsource)
    @log_do "store:save" "Transferring $(sprint(show, storage.dataset.name)) to storage"
    isdir(dirname(dest)) || mkpath(dirname(dest))
    if startswith(path.path, tempdir()) || (startswith(path.path, dest) && endswith(path.path, ".tmp"))
        mv(path.path, dest, force=true)
    else
        cp(path.path, dest, force=true)
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
    @log_do("store:save",
            "Writing $(sprint(show, storage.dataset.name)) to the store",
            atomic_write(dumpfile, from))
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
    @log_do("cache:save",
            "Saving $T form of $(sprint(show, loader.dataset.name)) to the store",
            Base.invokelatest(serialize, tempdest, value))
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
