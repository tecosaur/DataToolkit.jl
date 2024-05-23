"""
    MEMORISE_CACHE

A dictionary that stores in-memory copies of loaded datasets.

The key is a tuple `(collection_uuid, dataset_uuid, loader_hash, as)`, where
`collection_uuid` is the UUID of the collection containing the dataset,
`dataset_uuid` is the UUID of the dataset, `loader_hash` is the hash of all
loaders of the dataset, and `as` is the type of the loaded data.
"""
const MEMORISE_CACHE = Dict{Tuple{UUID, UUID, UInt, Type}, Any}()

"""
    memorise_read_a( <read1(dataset::DataSet, as::Type)> )

This advice keeps in-memory copies of all loaded datasets (that can safely be
re-used, currently we just avoid non-seekable `IO`), using `MEMORISE_CACHE`.

Part of `MEMORISE_PLUGIN`.
"""
function memorise_read_a(f::typeof(DataToolkitBase.read1), dataset::DataSet, as::Type)
        memorise = @something(get(dataset, "memorise"), get(dataset, "memorize", false))
        should_memorise = if memorise isa Bool
            memorise
        elseif memorise isa String
            as <: QualifiedType(memorise)
        elseif memorise isa Vector
            any(t -> as <: t, QualifiedType.(memorise))
        else
            false
        end
        stillvalid(::Any) = true
        stillvalid(info::IO) =
            isopen(info) && try
                seekstart(info)
                true
            catch _ false end
        if should_memorise
            dskey = (dataset.collection.uuid, dataset.uuid,
                        mapreduce(Store.rhash, xor, dataset.loaders), as)
            if haskey(MEMORISE_CACHE, dskey) && stillvalid(MEMORISE_CACHE[dskey])
                if should_log_event("memorise", dataset)
                    @info "Loading '$(dataset.name)' (as $as) from memory copy"
                end
                cache = MEMORISE_CACHE[dskey]
                (identity, (cache,))
            else
                docache = function (info)
                    MEMORISE_CACHE[dskey] = info
                    info
                end
                (docache, f, (dataset, as))
            end
        else
            (f, (dataset, as))
        end
    end

"""
Cache the results of data loaders in memory.
This requires `(dataset::DataSet, as::Type)` to consistently identify the same
loaded information.

### Enabling caching of a dataset

```toml
[[mydata]]
memorise = true
```

`memorise` can be a boolean value, a type that should be memorised, or a list of
types to be memorised.
"""
const MEMORISE_PLUGIN = Plugin("memorise", [Advice(0, memorise_read_a)])
