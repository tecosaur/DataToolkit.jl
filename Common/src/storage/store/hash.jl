# Without context

function Base.hash(dataset::DataSet, h::UInt)
    for field in (:uuid, :parameters, :storage, :loaders, :writers)
        h = hash(getfield(dataset, field), h)
    end
    h
end

function Base.hash(adt::AbstractDataTransformer, h::UInt)
    suphash = xor(hash.(adt.supports)...)
    driver = first(typeof(adt).parameters)
    h = hash(suphash, h)
    h = hash(adt.priority, h)
    h = hash(adt.parameters, h)
    h = hash(driver, h)
end

function Base.hash(ident::Identifier, h::UInt)
    for field in fieldnames(Identifier)
        h = hash(getfield(ident, field), h)
    end
    h
end

# With context

Base.hash((collection, obj)::Tuple{DataCollection, <:Any}, h::UInt) =
    chash(collection, obj, h)

function chash(collection::DataCollection, ds::DataSet, h::UInt)
    h = hash(ds.uuid, h)
    for field in (:parameters, :storage, :loaders, :writers)
        h = chash(collection, getfield(ds, field), h)
    end
    h
end

function chash(collection::DataCollection, adtl::Vector{AbstractDataTransformer}, h::UInt)
    chash.(Ref(collection), adtl, zero(UInt)) |>
        hs -> xor(h, hs...)
end

function chash(collection::DataCollection, adt::AbstractDataTransformer, h::UInt)
    suphash = xor(hash.(adt.supports)...)
    driver = first(typeof(adt).parameters)
    h = hash(suphash, h)
    h = hash(adt.priority, h)
    h = chash(collection, adt.parameters, h)
    h = hash(driver, h)
end

function chash(collection::DataCollection, ident::Identifier, h::UInt)
    hash(chash(collection, resolve(collection, ident, resolvetype=false), zero(UInt)),
         hash(ident, h))
end

function chash(collection::DataCollection, dict::Dict, h::UInt)
    [chash(collection, kv, zero(UInt)) for kv in dict] |>
        hs -> xor(h, hs...)
end

function chash(collection::DataCollection, pair::Pair, h::UInt)
    chash(collection, pair.second, chash(collection, pair.first, h))
end

function chash(collection::DataCollection, vec::Vector, h::UInt)
    for v in vec
        h = chash(collection, v, h)
    end
    h
end

chash(::DataCollection, obj::Any, h::UInt) = hash(obj, h)
