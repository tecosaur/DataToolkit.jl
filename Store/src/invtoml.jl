# Parsing from and serialising to an Inventory TOML file

function Base.convert(::Type{InventoryConfig}, spec::Dict{String, Any})
    getkey(key::Symbol, T::Type, noth::Bool=false) = if haskey(spec, String(key))
        if spec[String(key)] isa T; spec[String(key)]
        elseif spec[String(key)] === "nothing"; nothing
        else getfield(DEFAULT_INVENTORY_CONFIG, key) end
    else getfield(DEFAULT_INVENTORY_CONFIG, key) end
    InventoryConfig(getkey(:auto_gc, Int),
                    getkey(:max_age, Int, true),
                    getkey(:max_size, Int, true),
                    getkey(:recency_beta, Number),
                    getkey(:store_dir, String),
                    getkey(:cache_dir, String))
end

function Base.convert(::Type{CollectionInfo}, (uuid, spec)::Pair{String, Dict{String, Any}})
    for (key, type) in (("path", String),
                        ("seen", DateTime))
        if !haskey(spec, key)
            throw(ArgumentError("Spec dict does not contain the required key: $key"))
        elseif !(spec[key] isa type)
            throw(ArgumentError("Spec dict key $key is a $(typeof(spec[key])) not a $type"))
        end
    end
    CollectionInfo(parse(UUID, uuid), get(spec, "path", nothing),
                   get(spec, "name", nothing), spec["seen"])
end

"""
    parse(Checksum, checksum::String)

Parse a string representation of a checksum in the format `"type:value"`.

### Example

```jldoctest; setup = :(import DataToolkitStore.Checksum)
julia> parse(Checksum, "k12:cfb9a6a302f58e5a9b0c815bb7e8efb4")
Checksum(k12:cfb9a6a302f58e5a9b0c815bb7e8efb4)
```
"""
function Base.parse(::Type{Checksum}, checksum::String)
    typestr, valstr = split(checksum, ':', limit=2)
    hash = map(byte -> parse(UInt8, byte, base=16), Iterators.partition(valstr, 2))
    Checksum(Symbol(typestr), hash)
end

function Base.tryparse(::Type{Checksum}, checksum::String)
    count(':', checksum) == 1 || return
    typestr, valstr = split(checksum, ':', limit=2)
    all(c -> '0' <= c <= '9' || 'a' <= c <= 'f', valstr)
    ncodeunits(valstr) % 2 == 0 || return
    hash = map(byteind -> parse(UInt8, view(valstr, byteind), base=16),
               Iterators.partition(1:ncodeunits(valstr), 2))
    Checksum(Symbol(typestr), hash)
end

function Base.string(checksum::Checksum)
    iob = IOBuffer()
    print(iob, checksum.alg, ':')
    for b in checksum.hash
        print(iob, lpad(string(b, base=16), 2, '0'))
    end
    String(take!(iob))
end

function Base.show(io::IO, ::MIME"text/plain", checksum::Checksum)
    show(io, Checksum)
    print(io, "(", string(checksum), ')')
end

function Base.convert(::Type{StoreSource}, spec::Dict{String, Any})
    for (key, type) in (("recipe", String),
                        ("references", Vector{String}),
                        ("accessed", DateTime),
                        ("extension", String))
        if !haskey(spec, key)
            throw(ArgumentError("Spec dict does not contain the required key: $key"))
        elseif type <: Vector && isempty(spec[key])
        elseif !(spec[key] isa type)
            throw(ArgumentError("Spec dict key '$key' is a $(typeof(spec[key])) not a $type"))
        end
    end
    checksum = if haskey(spec, "checksum")
        tryparse(Checksum, spec["checksum"]) end
    StoreSource(parse(UInt64, spec["recipe"], base=16),
                map(UUID, spec["references"]),
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
        elseif type <: Vector && isempty(spec[key])
        elseif !(spec[key] isa type)
            throw(ArgumentError("Spec dict key $key is a $(typeof(spec[key])) not a $type"))
        end
    end
    packages = map(pkg -> Base.PkgId(parse(UUID, pkg["uuid"]), pkg["name"]),
                   spec["packages"])
    CacheSource(parse(UInt64, spec["recipe"], base=16),
                map(UUID, spec["references"]),
                spec["accessed"],
                parse.(QualifiedType, spec["types"]) .=>
                    parse.(UInt64, spec["typehashes"], base=16),
                packages)
end

function Base.convert(::Type{Dict}, conf::InventoryConfig)
    d = Dict{String, Any}()
    for key in (:auto_gc, :max_age, :max_size, :recency_beta, :store_dir, :cache_dir)
        if getfield(conf, key) != getfield(DEFAULT_INVENTORY_CONFIG, key)
            value = getfield(conf, key)
            d[String(key)] = if isnothing(value) "nothing" else value end
        end
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
    d = Dict{String, Any}(
        "recipe" => string(sinfo.recipe, base=16),
        "references" => map(string, sinfo.references),
        "accessed" => sinfo.accessed,
        "extension" => sinfo.extension)
    if !isnothing(sinfo.checksum)
        d["checksum"] = string(sinfo.checksum)
    end
    d
end

function Base.convert(::Type{Dict}, cinfo::CacheSource)
    Dict{String, Any}(
        "recipe" => string(cinfo.recipe, base=16),
        "references" => map(string, cinfo.references),
        "accessed" => cinfo.accessed,
        # FIXME the below line causes load time increases with Julia 1.11+:
        "types" => map(string ∘ first, cinfo.types),
        "typehashes" => map(t -> string(t, base=16), map(last, cinfo.types)),
        "packages" =>
            map(p -> Dict{String, Any}("name" => p.name, "uuid" => string(p.uuid)),
                cinfo.packages))
end

function Base.convert(::Type{Dict}, inv::Inventory)
    Dict{String, Any}(
        "inventory_version" => INVENTORY_VERSION,
        "inventory_last_gc" => inv.last_gc,
        "config" => convert(Dict, inv.config),
        "collections" => Dict{String, Any}(
            convert(Pair, cinfo) for cinfo in inv.collections),
        "store" => map(s -> convert(Dict, s), inv.stores),
        "cache" => map(c -> convert(Dict, c), inv.caches))
end

"""
A set of associations between keys that appear in the $INVENTORY_FILENAME
and alternative strings they will be sorted as.
"""
const INVENTORY_TOML_SORT_MAPPING =
    Dict(# top level
         "inventory_version" => "\0x01",
         "inventory_last_gc" => "\0x02",
         "config" => "\0x03",
         "collections" => "\0x04",
         "store" => "\0x05",
         "cache" => "\0x06",
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

function Base.write(inv::Inventory)
    if !trylock(inv.lock)
        # This uses a (hacky) workaround for same-task reentrant lock requirements.
        @log_do("store:inventory:waitpid",
                "Waiting for lock on inventory file to be released",
                begin lock(inv.lock); unlock(inv.lock.owned) end)
        lock(inv.lock.owned)
    end
    try
        atomic_write(inv.file.path, inv)
    finally
        unlock(inv.lock)
    end
end
