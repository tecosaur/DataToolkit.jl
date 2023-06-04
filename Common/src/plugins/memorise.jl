const MEMORISE_CACHE = Dict{Tuple{UUID, UUID, UInt, Type}, Any}()

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
const MEMORISE_PLUGIN = Plugin("memorise", [
    DataAdvice(
        0,
        function (f::typeof(DataToolkitBase._read), dataset::DataSet, as::Type)
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
        end)])
