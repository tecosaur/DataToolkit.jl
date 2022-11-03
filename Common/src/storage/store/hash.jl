# Without context

function Base.hash(dataset::DataSet, h::UInt)
    for field in (:uuid, :parameters, :storage, :loaders, :writers)
        h = hash(getfield(dataset, field), h)
    end
    h
end

function Base.hash(adt::AbstractDataTransformer, h::UInt)
    suphash = xor(hash.(adt.support)...)
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

"""
    chash(collection::DataCollection, obj, h::UInt)
    chash(obj::DataSet, h::UInt=0)                 # Convenience form
    chash(obj::AbstractDataTransformer, h::UInt=0) # Convenience form
Generate a hash of `obj` with respect to its `collection` context, which should
be *consistent* across sessions and cosmetic changes (chash = consistent hash).

This function has a catch-all method that falls back to calling `hash`, with
special implementations for the following `obj` types:
- `DataSet`
- `AbstractDataTransformer`
- `Identifier`
- `Dict`
- `Pair`
- `Vector`
"""
function chash end

chash(ds::DataSet, h::UInt=zero(UInt)) =
    chash(ds.collection, ds, h)

chash(adt::AbstractDataTransformer, h::UInt=zero(UInt)) =
    chash(adt.dataset.collection, adt, h)

function chash(collection::DataCollection, ds::DataSet, h::UInt)
    h = hash(ds.uuid, h)
    for field in (:parameters, :storage, :loaders, :writers)
        h = chash(collection, getfield(ds, field), h)
    end
    h
end

function chash(collection::DataCollection, adtl::Vector{AbstractDataTransformer}, h::UInt)
    reduce(xor, chash.(Ref(collection), adtl, zero(UInt)))
end

function chash(collection::DataCollection, adt::AbstractDataTransformer, h::UInt)
    suphash = reduce(xor, chash.(adt.support))
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

function chash(qt::QualifiedType)
    hash(qt.parentmodule,
         hash(qt.name,
              hash(chash.(qt.parameters))))
end

function chash(collection::DataCollection, dict::Dict, h::UInt)
    reduce(xor, [chash(collection, kv, zero(UInt)) for kv in dict],
           init=h)
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
chash(obj::Any, h::UInt=zero(UInt)) = hash(obj, h)
