# Management of inventories

"""
    load_inventory(path::String, create::Bool=true)

Load the inventory at `path`. If it does not exist, it will be created
so long as `create` is set to `true`.
"""
function load_inventory(path::String, create::Bool=true)
    if isfile(path)
        data = open(io -> TOML.parse(io), path)
        if !haskey(data, "inventory_version")
            if create && all(isspace, read(path, String))
                rm(path)
                load_inventory(path, create)
            else
                error("$path does not seem to be an inventory file")
            end
        elseif data["inventory_version"] != INVENTORY_VERSION
            error("Incompatible inventory version!")
        end
        file = MonitoredFile(path)
        last_gc = get(data, "inventory_last_gc", unix2datetime(0))
        config = convert(InventoryConfig, get(data, "config", Dict{String, Any}()))
        cmerkle = CachedMerkles(MonitoredFile(
            joinpath(dirname(path), config.store_dir, MERKLE_FILENAME)), [])
        cmerkle.file.mtime = 0.0 # To trigger refresh
        collections = [convert(CollectionInfo, key => val)
                    for (key, val) in get(data, "collections", Dict{String, Any}[])]
        stores = map(s -> convert(StoreSource, s), get(data, "store", Dict{String, Any}[]))
        caches = map(c -> convert(CacheSource, c), get(data, "cache", Dict{String, Any}[]))
        Inventory(file, LockFile(path, "Inventory"), cmerkle,
                  config, collections, stores, caches, last_gc)
    elseif create
        inventory = Inventory(
            MonitoredFile(path),
            LockFile(path, "Inventory"),
            CachedMerkles(MonitoredFile(
                joinpath(dirname(path), DEFAULT_INVENTORY_CONFIG.store_dir, MERKLE_FILENAME)), []),
            convert(InventoryConfig, Dict{String, Any}()),
            CollectionInfo[], StoreSource[],
            CacheSource[], now())
        isdir(dirname(path)) || mkpath(dirname(path))
        write(inventory)
        inventory
    else
        error("No inventory exists at $path")
    end
end

"""
    update_inventory!(path::String)
    update_inventory!(inventory::Inventory)

Find the inventory specified by `path`/`inventory` in the `INVENTORIES`
collection, and update it in-place. Should the inventory specified not be part
of `INVENTORIES`, it is added.

Returns the up-to-date `Inventory`.
"""
function update_inventory!(path::String)
    index = findfirst(inv -> inv.file.path == path, INVENTORIES)
    if isnothing(index)
        push!(INVENTORIES, load_inventory(path)) |> last
    else
        update_inventory!(INVENTORIES[index])
    end
end

function update_inventory!(inventory::Inventory)
    inv_mtime = mtime(inventory.file.path)
    if mtime(inventory.file.path) > inventory.file.mtime
        (; config, collections, stores, caches, last_gc) =
            load_inventory(inventory.file.path)
        inventory.config = config
        inventory.collections = collections
        inventory.stores = stores
        inventory.caches = caches
        inventory.last_gc = last_gc
        inventory.file.mtime = inv_mtime
    end
    inventory
end

"""
    modify_inventory!(modify_fn::Function (::Inventory) -> ::Any, inventory::Inventory)

Update `inventory`, modify it in-place with `modify_fn`, and the save the
modified `inventory`.
"""
function modify_inventory!(modify_fn::Function, inventory::Inventory)
    update_inventory!(inventory)
    modify_fn(inventory)
    write(inventory)
end

"""
    getinventory(collection::DataCollection)

Find the `Inventory` that is responsible for `collection`, creating it if
necessary.
"""
function getinventory(collection::DataCollection)
    storepath = get(get(collection, "store", Dict{String, Any}()),
                    "path", nothing)
    storepathabs = if isnothing(storepath)
        USER_STORE
    else
        cdir = if isnothing(collection.path)
            pwd()
        elseif  collection.path |> dirname |> basename == "Data.d"
            collection.path |> dirname |> dirname
        else
            collection.path |> dirname
        end
        joinpath(cdir, storepath)
    end
    invpath = joinpath(storepathabs, INVENTORY_FILENAME)
    index = findfirst(inv -> inv.file.path == invpath, INVENTORIES)
    if isnothing(index)
        push!(INVENTORIES, load_inventory(invpath)) |> last
    else
        INVENTORIES[index]
    end
end

"""
    getinventory()

Find the default user `Inventory`.
"""
function getinventory()
    if !isempty(INVENTORIES) && first(INVENTORIES).file.path == USER_INVENTORY
        first(INVENTORIES)
    else
        for inv in INVENTORIES
            if inv.file.path == USER_INVENTORY
                return inv
            end
        end
        push!(INVENTORIES, load_inventory(USER_INVENTORY)) |> last
    end
end

# Garbage Collection

"""
    files(inventory::Inventory)

Return all files referenced by `inventory`.
"""
function files(inv::Inventory)
    fs = [inv.file.path,
          joinpath(dirname(inv.file.path), inv.config.store_dir),
          joinpath(dirname(inv.file.path), inv.config.cache_dir),
          joinpath(dirname(inv.file.path), inv.config.store_dir, MERKLE_FILENAME)]
    append!(fs, map(Base.Fix1(storefile, inv), inv.stores))
    append!(fs, map(Base.Fix1(storefile, inv), inv.caches))
    fs
end

"""
    parsebytesize(size::AbstractString)

Parse a string representation of `size` bytes into an integer.

This accepts any decimal value before an SI-prefixed "B" / "iB" unit
(case-insensitive) with the "B" optionally omitted, separated and surrounded by
any amount of whitespace.

Note that the SI prefixes are case sensitive, e.g. "kiB" and "MiB" are
recognised, but "KiB" and "miB" are not.

## Examples

```jldoctest; setup = :(import DataToolkitStore.parsebytesize)
julia> parsebytesize("123B")
123

julia> parsebytesize("44 kiB")
45056

julia> parsebytesize("1.2 Mb")
1200000
```
"""
function parsebytesize(size::AbstractString)
    m = match(r"^\s*(\d+(?:\.\d*)?)\s*(|k|M|G|T|P)(|i|I)[bB]?\s*$", size)
    !isnothing(m) || throw(ArgumentError("Invalid byte size $(sprint(show, size))"))
    num, multiplier, ibi = m.captures
    exponent = findfirst(==(multiplier), ("", "k", "M", "G", "T", "P")) - 1
    if '.' in size
        round(Int, parse(Float64, num) * ifelse(isempty(ibi), 1000, 1024)^exponent)
    else
        parse(Int, num) * ifelse(isempty(ibi), 1000, 1024)^exponent
    end
end

"""
    humansize(bytes::Integer; digits::Int=2) -> (Int, String)

Copied from `DataToolkitCommon`, which see.
"""
function humansize(bytes::Integer; digits::Int=2)
    units = ("B", "KiB", "MiB", "GiB", "TiB", "PiB")
    magnitude = floor(Int, log(1024, max(1, bytes)))
    if 1024 <= bytes < 10.0^(digits-1) * 1024^magnitude
        magdigits = floor(Int, log10(bytes / 1024^magnitude)) + 1
        round(bytes / 1024^magnitude; digits = digits - magdigits)
    else
        round(Int, bytes / 1024^magnitude)
    end, units[1+magnitude]
end

"""
    printstats(inv::Inventory)
    printstats() # All inventories

Print statistics about `inv`.

TODO elaborate
"""
function printstats(inv::Inventory)
    function storesize(store)
        file = storefile(inv, store)
        Int(isfile(file) && filesize(file))
    end
    printstyled(lpad("Tracking", MSG_LABEL_WIDTH), bold=true, color=:green)
    println(' ', length(inv.collections), " collection",
            ifelse(length(inv.collections) == 1, "", "s"))
    storesizes = map(storesize, inv.stores)
    printstyled(lpad("Stored", MSG_LABEL_WIDTH), bold=true, color=:green)
    println(' ', length(inv.stores), " files, taking up $(join(humansize(sum(storesizes))))")
    cachesizes = map(storesize, inv.caches)
    printstyled(lpad("Cached", MSG_LABEL_WIDTH), bold=true, color=:green)
    println(' ', length(inv.caches), " data sets, taking up $(join(humansize(sum(cachesizes))))")
    printstyled(lpad("Largest", MSG_LABEL_WIDTH), bold=true, color=:green)
    println(" stored file is $(join(humansize(maximum(storesizes, init=0))))",
            ", cache file is $(join(humansize(maximum(cachesizes, init=0))))")
    printstyled(lpad("Total", MSG_LABEL_WIDTH), bold=true, color=:green)
    totalsize = sum(storesizes) + sum(cachesizes)
    print(' ', join(humansize(totalsize)))
    if !isnothing(inv.config.max_size)
        print(" / ", join(humansize(inv.config.max_size)),
              " (", floor(Int, 100 * totalsize / inv.config.max_size), "%)")
    end
    print('\n')
end

function printstats()
    if length(INVENTORIES) == 1
        printstats(first(INVENTORIES))
    else
        for inv in INVENTORIES
            printstyled("Store: ",
                        if dirname(inv.file.path) == USER_STORE
                            "(user)"
                        else
                            dirname(inv.file.path)
                        end, '\n', color=:magenta, bold=true)
            printstats(inv)
        end
    end
end

"""
    garbage_collect!(inv::Inventory; log::Bool=true, dryrun::Bool=false, trimmsg::Bool=false)

Examine `inv`, and garbage collect old entries.

If `log` is set, an informative message is printed giving an overview
of actions taken.

If `dryrun` is set, no actions are taken.

If `trimmsg` is set, a message about any sources removed by trimming is emitted.
"""
function garbage_collect!(inv::Inventory; log::Bool=true, dryrun::Bool=false, trimmsg::Bool=false)
    inv.file.writable || return
    (; active_collections, live_collections, ghost_collections, dead_collections) =
        scan_collections(inv)
    dryrun || deleteat!(inv.collections, Vector{Int}(indexin(dead_collections, getfield.(inv.collections, :uuid))))
    inactive_collections = live_collections ∪ ghost_collections
    (; orphan_sources, num_recipe_checks) =
        refresh_sources!(inv; active_collections, inactive_collections, dryrun)
    if log
        printstyled(lpad("Scanned", MSG_LABEL_WIDTH), bold=true, color=:green)
        num_scanned_collections = length(active_collections) + length(live_collections)
        println(' ', num_scanned_collections, " collection",
                ifelse(num_scanned_collections == 1, "", "s"))
        if !isempty(ghost_collections) || !isempty(dead_collections)
            printstyled(lpad("Inactive", MSG_LABEL_WIDTH), bold=true, color=:green)
            print(" collections: ",
                  length(ghost_collections) + length(dead_collections),
                  " found")
            if !isempty(dead_collections)
                print(", ", length(dead_collections), " beyond the maximum age")
            end
            print('\n')
        end
        nsources = length(inv.stores) + length(inv.caches) + length(orphan_sources)
        printstyled(lpad("Checked", MSG_LABEL_WIDTH), bold=true, color=:green)
        println(' ', nsources, " cached item",
                ifelse(nsources == 1, "", "s"),
                " (", num_recipe_checks, " recipe check",
                ifelse(num_recipe_checks == 1, "", "s"), ")")
    end
    orphan_files = let fs = readdir(dirname(inv.file.path), join=true)
        storedir = joinpath(dirname(inv.file.path), inv.config.store_dir)
        isdir(storedir) && append!(fs, readdir(storedir, join=true))
        cachedir = joinpath(dirname(inv.file.path), inv.config.cache_dir)
        isdir(cachedir) && append!(fs, readdir(cachedir, join=true))
        setdiff(fs, files(inv))
    end
    deleted_bytes = 0
    for f in orphan_files
        if dirname(f) == dirname(inv.file.path)
            startswith(basename(f), "Inventory.toml-") && endswith(f, ".part") && continue
            @warn "Found an unexpected $(ifelse(isdir(f), "subfolder", "file")) in the inventory folder, \
                    this is quite irregular ($(relpath(f, inv.file.path))) \
                    — $(ifelse(dryrun, "would remove", "removing"))"
        end
        if isdir(f)
            dryrun || rm(f, force=true, recursive=true)
        else
            deleted_bytes += stat(f).size
            dryrun || rm(f, force=true)
        end
    end
    truncated_sources, truncsource_bytes = garbage_trim_size!(inv; dryrun)
    dryrun || for source in truncated_sources
        file = storefile(inv, source)
        isfile(file) && rm(file, force=true)
    end
    if log
        if !isempty(truncated_sources) && trimmsg
            printstyled("Data Toolkit Store", color=:magenta, bold=true)
            println(" trimmed ", length(truncated_sources), " items (",
                    join(humansize(truncsource_bytes)), ") to avoid going over the maximum size")
        end
        deleted_bytes += truncsource_bytes
        printstyled(lpad(ifelse(dryrun, "Would remove", "Removed"), MSG_LABEL_WIDTH),
                    bold=true, color=:green)
        if isempty(dead_collections) && isempty(orphan_sources) && isempty(orphan_files) && isempty(truncated_sources)
            println(" nothing")
        else
            length(dead_collections) > 0 &&
                print(' ', length(dead_collections), " collection",
                      ifelse(length(dead_collections) == 1, "", "s"))
            length(orphan_sources) > 0 &&
                print(ifelse(!isempty(dead_collections), ", ", " "),
                      length(orphan_sources), " cached item",
                      ifelse(length(orphan_sources) == 1, "", "s"))
            orphan_delta = length(orphan_files) - length(orphan_sources)
            orphan_delta > 0 &&
                print(ifelse(!isempty(dead_collections) || !isempty(orphan_sources),
                             ", ", " "),
                      orphan_delta, " orphan file",
                      ifelse(orphan_delta == 1, "", "s"))
            !isempty(truncated_sources) &&
                print(ifelse(!isempty(dead_collections) || !isempty(orphan_sources) || orphan_delta > 0,
                             ", ", " "),
                      length(truncated_sources), " large item",
                      ifelse(length(truncated_sources) == 1, "", "s"))
            if deleted_bytes > 0
                print('\n')
                removedsize, removedunits = humansize(deleted_bytes)
                printstyled(lpad(ifelse(dryrun, "Would free", "Freed"), MSG_LABEL_WIDTH),
                            bold=true, color=:green)
                print(" $removedsize$removedunits")
            end
            print('\n')
        end
    end
    if !dryrun
        inv.last_gc = now()
        write(inv)
    end
end

"""
    garbage_collect!(; log::Bool=true, kwargs...)

Garbage collect all inventories.
"""
function garbage_collect!(; log::Bool=true, kwargs...)
    if length(INVENTORIES) == 1
        garbage_collect!(first(INVENTORIES); log, kwargs...)
    else
        for inv in INVENTORIES
            log && printstyled(
                "Store: ",
                if dirname(inv.file.path) == USER_STORE
                    "(user)" else dirname(inv.file.path) end,
                '\n', color=:magenta, bold=true)
            garbage_collect!(inv; log, kwargs...)
        end
    end
end

"""
    garbage_trim_size!(inv::Inventory; dryrun::Bool=false)

If the sources in `inv` exceed the maximum size, remove sources in order of
their `size_recency_scores` until `inv` returns below its maximum size.

If `dryrun` is set, no action is taken.
"""
function garbage_trim_size!(inv::Inventory; dryrun::Bool=false)
    !isnothing(inv.config.max_size) || return (SourceInfo[], 0)
    allsources = vcat(inv.stores, inv.caches)
    allsizes = map(f -> Int(isfile(f) && stat(f).size), storefile.(Ref(inv), allsources))
    if sum(allsizes, init=0) > inv.config.max_size
        allscores = size_recency_scores(inv, allsources, inv.config.recency_beta)
        totalsize = sum(allsizes)
        removed = SourceInfo[]
        for (source, source_size) in zip(allsources[sortperm(allscores, rev=true)],
                                         allsizes[sortperm(allscores, rev=true)])
            totalsize > inv.config.max_size || break
            push!(removed, source)
            totalsize -= source_size
            dryrun || if source isa StoreSource
                index = findfirst(==(source), inv.stores)
                deleteat!(inv.stores, index)
            else # CacheSource
                index = findfirst(==(source), inv.caches)
                deleteat!(inv.caches, index)
            end
        end
        removed, sum(allsizes) - totalsize
    else
        SourceInfo[], 0
    end
end

"""
    size_recency_scores(inventory::Inventory, sources::Vector{SourceInfo}, β::Number=1)

Produce a combined score for each of `sources` in `inventory` based on the size
and (access) recency of the source, with small recent files scored higher than
large older files. Files that do not exist are given a score of 0.0.

The combined score is a weighted harmonic mean, inspired by the F-score. More
specifically, the combined score is ``(1 + \\beta^2) \\cdot \\frac{t \\cdot
s}{\\beta^2 t + s}`` where ``\\beta`` is the recency factor, ``t \\in [0, 1]``
is the time score, and ``s \\in [0, 1]`` is the size score. When `β` is
negative, the ``\\beta^2`` weighting is applied to ``s`` instead.
"""
function size_recency_scores(inventory::Inventory, sources::Vector{SourceInfo}, β::Number=1)
    sizes = Int[]
    times = Float64[]
    for source in sources
        push!(times, datetime2unix(source.accessed))
        file = storefile(inventory, source)
        if isfile(file)
            fstat = stat(file)
            push!(sizes, fstat.size)
        else
            push!(sizes, 0)
        end
    end
    largest = maximum(sizes)
    time_min, time_max = extrema(times)
    sscores = sizes ./ largest
    tscores = @. (time_max - times) / (time_max - time_min)
    map(if β >= 0
            (s, t)::Tuple -> (1 + β^2) * (s * t) / (s + β^2 * t)
        else
            (s, t)::Tuple -> (1 + β^2) * (s * t) / (β^2 * s + t)
        end,
        zip(sscores, tscores))
end

"""
    scan_collections(inv::Inventory)

Examine each collection in `inv`, and sort them into the following categories:
- `active_collections`: data collections which are part of the current `STACK`
- `live_collections`: data collections who still exist, but are not part of `STACK`
- `ghost_collections`: collections that do not exist, but have been seen within the maximum age
- `dead_collections`: collections that have not been seen within the maximum age

These categories are returned with a named tuple of the following form:

```julia
(; active_collections::Dict{UUID, Set{UInt64}},
   live_collections::Set{UUID},
   ghost_collections::Set{UUID},
   dead_collections::Vector{UUID})
```

The `active_collections` value gives both the data collection UUIDs, as well
as all known recipe hashes.
"""
function scan_collections(inv::Inventory)
    active_collections = Dict{UUID, Set{UInt64}}()
    live_collections = Set{UUID}()
    ghost_collections = Set{UUID}()
    dead_collections = Vector{UUID}()
    days_since(t::DateTime) = convert(Millisecond, now() - t).value / (1000*60*60*24)
    for collection in inv.collections
        if !isnothing(collection.path) && isfile(collection.path)
            cdata = try
                open(TOML.parse, collection.path)
            catch err
                @warn "Unable to parse $(collection.path)" err
                continue
            end
            if haskey(cdata, "uuid") && parse(UUID, cdata["uuid"]) == collection.uuid
                if collection.uuid ∈ getfield.(STACK, :uuid)
                    ids = Set{UInt64}()
                    for dataset in getlayer(collection.uuid).datasets
                        for storage in dataset.storage
                            push!(ids, rhash(storage))
                        end
                        for loader in dataset.loaders
                            push!(ids, rhash(loader))
                        end
                    end
                    active_collections[collection.uuid] = ids
                else
                    push!(live_collections, collection.uuid)
                end
            elseif isnothing(inv.config.max_age) || days_since(collection.seen) <= inv.config.max_age
                push!(ghost_collections, collection.uuid)
            else
                push!(dead_collections, collection.uuid)
            end
        elseif days_since(collection.seen) <= inv.config.max_age
            push!(ghost_collections, collection.uuid)
        else
            push!(dead_collections, collection.uuid)
        end
    end
    (; active_collections, live_collections, ghost_collections, dead_collections)
end

"""
    refresh_sources!(inv::Inventory; inactive_collections::Set{UUID},
                     active_collections::Dict{UUID, Set{UInt64}})

Update the listed `references` of each source in `inv`, such that
only references that are part of either `inactive_collections` or
`active_collections` are retained.

References to `active_collections` also are checked against the given recipe
hash and the known recipe hashes.

Sources with no references after this update are considered orphaned and removed.

The result is a named tuple giving a list of orphaned sources and the number of
recipe checks that occurred.
"""
function refresh_sources!(inv::Inventory; active_collections::Dict{UUID, Set{UInt64}},
                          inactive_collections::Set{UUID}, dryrun::Bool=false)
    orphan_sources = SourceInfo[]
    num_recipe_checks = 0
    for sources in (inv.stores, inv.caches)
        let i = 1; while i <= length(sources)
            source = sources[i]
            # TODO avoid permanantly modifying during dryrun
            filter!(source.references) do r
                if haskey(active_collections, r)
                    num_recipe_checks += 1
                    source.recipe ∈ active_collections[r] &&
                        if source isa StoreSource
                            true
                        elseif all(Base.root_module_exists, source.packages)
                            true
                        else
                            all(@. rhash(typeify(first(source.types))) == last(source.types))
                        end
                else
                    r ∈ inactive_collections
                end
            end
            if isempty(source.references) || !isfile(storefile(inv, source))
                push!(orphan_sources, source)
                if dryrun
                    i += 1
                else
                    deleteat!(sources, i)
                end
            else
                i += 1
            end
        end end
    end
    (; orphan_sources, num_recipe_checks)
end

"""
    expunge!(inventory::Inventory, collection::CollectionInfo; dryrun::Bool=false)

Remove `collection` and all sources only used by `collection` from `inventory`.

If `dryrun` is set, no action is taken.
"""
function expunge!(inventory::Inventory, collection::CollectionInfo; dryrun::Bool=false)
    cindex = findfirst(==(collection), inventory.collections)
    isnothing(cindex) || deleteat!(inventory.collections, cindex)
    removed_sources = SourceInfo[]
    inventory.file.writable || return removed_sources
    for sources in (inventory.stores, inventory.caches)
        i = 1; while i <= length(sources)
            source = sources[i]
            if (index = findfirst(collection.uuid .== source.references)) |> !isnothing
                dryrun || deleteat!(source.references, index)
                if isempty(source.references)
                    push!(removed_sources, source)
                    dryrun || deleteat!(sources, i)
                    file = storefile(inventory, source)
                    dryrun || isfile(file) && rm(file, force=true)
                else
                    i += 1
                end
            else
                i += 1
            end
        end
    end
    dryrun || write(inventory)
    removed_sources
end

"""
    fetch!(storer::DataStorage)

If `storer` is storable (either by default, or explicitly enabled), open it, and
presumably save it in the Store along the way.
"""
function fetch!(@nospecialize(storer::DataStorage))
    if shouldstore(storer) || @getparam(storer."save"::Bool, false) === true
        for type in (FilePath, IO, IOStream)
            if QualifiedType(type) in storer.type
                handle = @advise storage(storer, type, write=false)
                if handle isa IO
                    close(handle)
                    return true
                elseif !isnothing(handle)
                    return true
                end
            end
        end
    end
    false
end

"""
    fetch!(dataset::DataSet)

Call `fetch!` on each storage backend of `dataset`.
"""
fetch!(dataset::DataSet) = foreach(fetch!, dataset.storage)

"""
    fetch!(collection::DataCollection)

When `collection` uses the `store` plugin, call `fetch!` on all of its
data sets.
"""
function fetch!(collection::DataCollection)
    if "store" in collection.plugins
        foreach(fetch!, collection.datasets)
    end
end
