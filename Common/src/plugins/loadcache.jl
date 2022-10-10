const LOADCACHE_DEFAULT_FOLDER = "loadcache"

function loadcache_file(loader::DataLoader, source::Any, as::Type)
    # Obtain a consistant hash based on this loader and the
    # defined storage backends.
    lhash = chash(loader,
                  chash(loader.dataset.collection,
                        loader.dataset.storage,
                        UInt(0)))
    (lhash,
     joinpath(
         # Base folder
         if !isnothing(loader.dataset.collection.path)
             dirname(loader.dataset.collection.path)
         else
             pwd()
         end,
         # Cache folder
         @something(get(loader, "loadcache"),
                    get(get(loader.dataset.collection, "loadcache", Dict()),
                        "folder", LOADCACHE_DEFAULT_FOLDER)),
         # Dataset
         string(loader.dataset.uuid),
         # Loader
         string(lhash, base=16),
         string(typeof(source), "-to-", as, ".jld2")))
end

loadcache_isstorable(T::Type) =
    if T <: IOStream ||
        QualifiedType(Base.typename(T).wrapper) == QualifiedType(:TranscodingStreams, :TranscodingStream)
        false
    else
        true
    end

"""
    Plugin("loadcache", [...])
Cache the results of data loaders using **JLD2**. Cache file paths are determined by
the dataset UUID and a hash of the loader and storage backends.

It is important to note that this comes with the limitations of JLD2, i.e. some
data types will not be able to be cachced effectively, such as `IOStream`.

### Enabling caching of a loader

To cache the result of an individual loader, set the `cache` parameter.

```toml
[[mydata.loader]]
driver = "backend"
cache = true
```

To apply this setting in bulk, the `defaults` plugin may be of interest.
With it, all loaders can be cached with the following:

```toml
[config.defaults.loader.$(DEFAULTS_ALL)]
cache = true
```

### Configuring the cache directory

```toml
[config.loadcache]
folder = "loadcache" # the default
```
"""
const LOADCACHE_PLUGIN = Plugin("loadcache", [
    function (post::Function, f::typeof(load), loader::DataLoader, source::Any, as::Type)
        if loadcache_isstorable(as) && get(loader, "cache", false) == true
            @use JLD2
            lhash, path = loadcache_file(loader, source, as)
            if !isdir(dirname(path))
                mkpath(dirname(path))
            end
            if isfile(path)
                cache = JLD2.load(path, "data")
                (post, identity, (cache,))
            else
                docache = function (data)
                    JLD2.jldsave(path; data,
                                 dataset = loader.dataset.uuid,
                                 hash = lhash)
                    data
                end
                (post ∘ docache, f, (loader, source, as))
            end
        else
            (post, f, (loader, source, as))
        end
    end])
