const INVENTORY_VERSION = 0

INVENTORY::Union{Inventory, Nothing} = nothing

const DEFAULT_INVENTORY_CONFIG = (; max_age = 30 )

# Reading and writing

function Base.convert(::Type{InventoryConfig}, spec::Dict{String, Any})
    max_age = if haskey(spec, "max_age") && spec["max_age"] isa Int
        spec["max_age"]
    else DEFAULT_INVENTORY_CONFIG.max_age end
    InventoryConfig(max_age)
end

function Base.convert(::Type{CollectionInfo}, (uuid, spec)::Pair{String, Dict{String, Any}})
    for (key, type) in (("path", String),)
        if !haskey(spec, key)
            throw(ArgumentError("Spec dict does not contain the required key: $key"))
        elseif !(spec[key] isa type)
            throw(ArgumentError("Spec dict key $key is a $(typeof(spec[key])) not a $type"))
        end
    end
    CollectionInfo(parse(UUID, uuid), get(spec, "path", nothing),
                   get(spec, "name", nothing), spec["seen"])
end

function parsechecksum(checksum::String)
    typestr, valstr = split(checksum, ':')
    type = Symbol(typestr)
    val = if type === :crc32c
        parse(UInt32, valstr, base=16)
    elseif type === :xxhash
        parse(UInt128, valstr, base=16)
    end
    type, val
end

function Base.convert(::Type{StoreSource}, spec::Dict{String, Any})
    for (key, type) in (("recipe", String),
                        ("references", Vector{String}),
                        ("accessed", DateTime),
                        ("extension", String))
        if !haskey(spec, key)
            throw(ArgumentError("Spec dict does not contain the required key: $key"))
        elseif !(spec[key] isa type)
            throw(ArgumentError("Spec dict key $key is a $(typeof(spec[key])) not a $type"))
        end
    end
    checksum = if haskey(spec, "checksum")
        parsechecksum(spec["checksum"]) end
    StoreSource(parse(UInt64, spec["recipe"], base=16),
                parse.(UUID, spec["references"]),
                spec["accessed"], checksum,
                spec["extension"])
end

function Base.convert(::Type{CacheSource}, spec::Dict{String, Any})
    for (key, type) in (("recipe", String),
                        ("references", Vector{String}),
                        ("accessed", DateTime),
                        ("types", Vector{String}),
                        ("typehashes", Vector{String}),
                        ("packages", Vector))
        if !haskey(spec, key)
            throw(ArgumentError("Spec dict does not contain the required key: $key"))
        elseif !(spec[key] isa type)
            throw(ArgumentError("Spec dict key $key is a $(typeof(spec[key])) not a $type"))
        end
    end
    packages = map(pkg -> Base.PkgId(parse(UUID, pkg["uuid"]), pkg["name"]),
                   spec["packages"])
    CacheSource(parse(UInt64, spec["recipe"], base=16),
                parse.(UUID, spec["references"]),
                spec["accessed"],
                parse.(QualifiedType, spec["types"]) .=>
                    parse.(UInt64, spec["typehashes"], base=16),
                packages)
end

function Base.convert(::Type{Dict}, conf::InventoryConfig)
    d = Dict{String, Any}()
    if conf.max_age != DEFAULT_INVENTORY_CONFIG.max_age
        d["max_age"] = conf.max_age
    end
    d
end

function Base.convert(::Type{Pair}, cinfo::CollectionInfo)
    d = Dict{String, Any}("seen" => cinfo.seen)
    if !isnothing(cinfo.path)
        d["path"] = cinfo.path
    end
    if !isnothing(cinfo.name)
        d["name"] = cinfo.name
    end
    string(cinfo.uuid) => d
end

function Base.convert(::Type{Dict}, sinfo::StoreSource)
    d = Dict{String, Any}("recipe" => string(sinfo.recipe, base=16),
                          "references" => string.(sinfo.references),
                          "accessed" => sinfo.accessed,
                          "extension" => sinfo.extension)
    if !isnothing(sinfo.checksum)
        d["checksum"] = string(sinfo.checksum[1], ':',
                               string(sinfo.checksum[2], base=16))
    end
    d
end

function Base.convert(::Type{Dict}, sinfo::CacheSource)
    Dict{String, Any}("recipe" => string(sinfo.recipe, base=16),
                      "references" => string.(sinfo.references),
                      "accessed" => sinfo.accessed,
                      "types" => string.(first.(sinfo.types)),
                      "typehashes" => string.(last.(sinfo.types), base=16),
                      "packages" =>
                          map(p -> Dict("name" => p.name,
                                        "uuid" => string(p.uuid)),
                              sinfo.packages))
end

function Base.convert(::Type{Dict}, inv::Inventory)
    Dict{String, Any}("inventory_version" => INVENTORY_VERSION,
                      "config" => convert(Dict, inv.config),
                      "collections" => Dict{String, Any}(
                          convert(Pair, cinfo) for cinfo in inv.collections),
                      "store" => convert.(Dict, inv.stores),
                      "cache" => convert.(Dict, inv.caches))
end

const INVENTORY_TOML_SORT_MAPPING =
    Dict(# top level
         "inventory_version" => "\0x01",
         "config" => "\0x02",
         "collections" => "\0x03",
         "store" => "\0x04",
         "cache" => "\0x05",
         # store/cache item
         "recipe" => "\0x01",
         "accessed" => "\0x02",
         "references" => "\0x03",
         "types" => "\0x04",
         "typehashes" => "\0x05",
         "checksum" => "\0x06",
         "extension" => "\0x07",
         # packages
         "name" => "\0x01",
         "uuid" => "\0x02")

function Base.write(io::IO, inv::Inventory)
    keygen(key) = get(INVENTORY_TOML_SORT_MAPPING, key, key)
    TOML.print(io, convert(Dict, inv), sorted=true, by=keygen)
end

Base.write(inv::Inventory) = write(inv.file.path, inv)

function load_inventory(path::String)
    file = InventoryFile(path, mtime(path))
    data = open(io -> TOML.parse(io), path)
    config = convert(InventoryConfig, get(data, "config", Dict{String, Any}()))
    collections = [convert(CollectionInfo, key => val)
                   for (key, val) in get(data, "collections", Dict{String, Any}[])]
    stores = convert.(StoreSource, get(data, "store", Dict{String, Any}[]))
    caches = convert.(CacheSource, get(data, "cache", Dict{String, Any}[]))
    Inventory(file, config, collections, stores, caches)
end

function update_inventory()
    global INVENTORY
    if isnothing(INVENTORY)
        path = joinpath(STORE_DIR, "Inventory.toml")
        if isfile(path)
            INVENTORY = load_inventory(path)
        else
            INVENTORY = Inventory(
                InventoryFile(path, time()),
                convert(InventoryConfig, Dict{String, Any}()),
                CollectionInfo[],
                StoreSource[],
                CacheSource[])
            write(INVENTORY)
        end
    else
        update_inventory(INVENTORY)
    end
    INVENTORY
end

function update_inventory(inventory::Inventory)
    if mtime(inventory.file.path) > inventory.file.recency
        inventory = load_inventory(inventory.file.path)
    end
    inventory
end

function modify_inventory(modify_fn::Function, inventory::Inventory=INVENTORY)
    update_inventory(inventory)
    modify_fn()
    write(inventory)
end

# Garbage Collection

"""
    garbage_collect!(inv::Inventory, log::Bool=true)

Examine `inv`, and garbage collect old entries.

If `log` is set, an informative message is printed giving an overview
of actions taken.
"""
function garbage_collect!(inv::Inventory, log::Bool=true)
    (; active_collections, live_collections, ghost_collections, dead_collections) =
        scan_collections(inv)
    deleteat!(inv.collections, Vector{Int}(indexin(dead_collections, getfield.(inv.collections, :uuid))))
    inactive_collections = live_collections ∪ ghost_collections
    (; orphan_sources, num_recipe_checks) =
        refresh_sources!(inv; inactive_collections, active_collections)
    if log
        printstyled("   Scanned", bold=true, color=:green)
        println(' ', length(live_collections), " collection",
                ifelse(length(live_collections) == 1, "", "s"))
        if !isempty(ghost_collections) || !isempty(dead_collections)
            printstyled("  Inactive", bold=true, color=:green)
            print(" collections: ",
                  length(ghost_collections) + length(dead_collections),
                  " found")
            if !isempty(dead_collections)
                print(", ", length(dead_collections), " beyond the maximum age")
            end
            print('\n')
        end
        nsources = length(inv.stores) + length(inv.caches) + length(orphan_sources)
        printstyled("   Checked", bold=true, color=:green)
        println(' ', nsources, " cached item",
                ifelse(nsources == 1, "", "s"),
                " (", num_recipe_checks, " recipe check",
                ifelse(num_recipe_checks == 1, "", "s"), ")")
        printstyled("   Removed", bold=true, color=:green)
        if isempty(dead_collections) && isempty(orphan_sources)
            println(" nothing")
        else
            println(' ', length(dead_collections), " collection",
                    ifelse(length(dead_collections) == 1, "", "s"),
                    ", ", length(orphan_sources), " cached item",
                    ifelse(length(orphan_sources) == 1, "", "s"))
        end
    end
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
        if isfile(collection.path)
            cdata = open(io -> TOML.parse(io), collection.path)
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
            elseif days_since(collection.seen) <= inv.config.max_age
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
recipe checks that occured.
"""
function refresh_sources!(inv::Inventory; inactive_collections::Set{UUID},
                                active_collections::Dict{UUID, Set{UInt64}})
    orphan_sources = SourceInfo[]
    num_recipe_checks = 0
    for sources in (inv.stores, inv.caches)
        let i = 1; while i <= length(sources)
            source = sources[i]
            filter!(source.references) do r
                r ∈ inactive_collections ||
                    if haskey(active_collections, r)
                        num_recipe_checks += 1
                        source.recipe ∈ active_collections[r]
                else false end
            end
            if isempty(source.references)
                push!(orphan_sources, source)
                deleteat!(sources, i)
            else
                i += 1
            end
        end end
    end
    (; orphan_sources, num_recipe_checks)
end
