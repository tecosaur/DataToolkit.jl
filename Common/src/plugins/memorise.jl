const MEMORISE_CACHE = Dict{Tuple{DataSet, Type}, Any}()

"""
    Plugin("memorise", [...])
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
        function (post::Function, f::typeof(DataToolkitBase._read), dataset::DataSet, as::Type)
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
            if should_memorise
                if haskey(MEMORISE_CACHE, (dataset, as))
                    if should_log_event("memorise", dataset)
                        @info "Loading '$(dataset.name)' (as $as) from memory copy"
                    end
                    cache = MEMORISE_CACHE[(dataset, as)]
                    (post, identity, (cache,))
                else
                    docache = function (info)
                        MEMORISE_CACHE[(dataset, as)] = info
                        info
                    end
                    (post ∘ docache, f, (dataset, as))
                end
            else
                (post, f, (dataset, as))
            end
        end)])
