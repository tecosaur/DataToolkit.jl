"""
    rhash(loader::DataLoader{driver}, h::UInt=zero(UInt)) where {driver}

Hash the *recipe* specified by `loader`, or more specifically the various
aspects of `storage` that could affect the loaded result.

The hash should be consistent across sessions and cosmetic changes.
"""
function rhash(loader::DataLoader{driver}, h::UInt=zero(UInt)) where {driver}
    h = hash(driver, h)
    h = @advise rhash(loader.dataset.collection, copy(loader.parameters), h)
    # The only field of the parent data set that should affect the loaded
    # result is the storage drivers used, so let's just hash all of them.
    # This is likely over-zealous, but it's better to be overly cautions.
    # We still skip the priority though.
    for storage in loader.dataset.storage
        h = rhash(storage, h)
    end
    for qtype in loader.type
        h = rhash(qtype, h)
    end
    h
end

"""
    rhash(storage::DataStorage{driver}, h::UInt=zero(UInt)) where {driver}

Hash the *recipe* specified by `storage`, or more specifically the various
aspects of `storage` that could affect the result.
"""
function rhash(storage::DataStorage{driver}, h::UInt=zero(UInt)) where {driver}
    h = hash(driver, h)
    h = @advise rhash(storage.dataset.collection, copy(storage.parameters), h)
    # The result of the storage driver should /not/ be materially affected by
    # the parent dataset, or it's priority, and so we skip those fields.
    for qtype in storage.type
        h = rhash(qtype, h)
    end
    h
end

rhash(::DataCollection, adt::AbstractDataTransformer, h::UInt=zero(UInt)) =
    rhash(adt, h)

@doc """
    rhash(collection::DataCollection, x, h::UInt)

Hash `x` with respect to `collection`, with special behaviour for
the following types:
- `SmallDict`
- `Vector`
- `Pair`
- `Type`
- `QualifiedType`
""" rhash

"""
    rhash(collection::DataCollection, dict::SmallDict, h::UInt=zero(UInt)) # Helper method

Individually hash each entry in `dict`, and then `xor` the results so the
final value is independant of the ordering.
"""
rhash(collection::DataCollection, dict::SmallDict, h::UInt=zero(UInt)) =
    reduce(xor, [rhash(collection, kv, zero(UInt)) for kv in dict],
           init=h)

rhash(collection::DataCollection, pair::Pair, h::UInt) =
    rhash(collection, pair.second, rhash(collection, pair.first, h))

function rhash(collection::DataCollection, vec::Vector, h::UInt)
    for v in vec
        h = rhash(collection, v, h)
    end
    h
end

rhash(::DataCollection, obj::String, h::UInt) = hash(obj, h)
rhash(::DataCollection, obj::Number, h::UInt) = hash(obj, h)
rhash(::DataCollection, obj::Symbol, h::UInt) = hash(obj, h)

"""
    rhash(::Type{T}, h::UInt) # Helper method

Hash the field names and types of `T` recursively,
or `T` is a primitive type hash the name and parent module name.
"""
function rhash(::Type{T}, h::UInt=zero(UInt)) where {T}
    if !isconcretetype(T)
        h = hash(T, h)
    else
        h = hash(nameof(T), h)
        for param in Base.unwrap_unionall(T).parameters
            h = rhash(param, h)
        end
        for fname in fieldnames(T)
            h = hash(fname, h)
        end
        for ftype in fieldtypes(T)
            h = rhash(ftype, h)
        end
    end
    h
end
rhash(::DataCollection, obj::Type, h::UInt) = rhash(obj, h)

function rhash(qt::QualifiedType, h::UInt=zero(UInt))
    hash(qt.parentmodule,
         hash(qt.name,
              hash(rhash.(qt.parameters), h)))
end

# Fallbacks
function rhash(c::DataCollection, obj::T, h::UInt) where {T}
    if isprimitivetype(T)
        hash(obj, rhash(T, h))
    else
        reduce(xor,
               (rhash(c, getfield(obj, f), zero(UInt))
                for f in fieldnames(T)),
               init=rhash(QualifiedType(T), h))
    end
end

rhash(obj::Any, h::UInt=zero(UInt)) = hash(obj, h)
