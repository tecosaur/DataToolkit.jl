const STORE_GC_CONFIG_INFO = """
Four (system-wide) settings determine garbage collection behaviour:
1. `auto_gc` (default $(DEFAULT_INVENTORY_CONFIG.auto_gc)): How often to
   automatically run garbage collection (in hours). Set to a non-positive value
   to disable.
2. `max_age` (default $(DEFAULT_INVENTORY_CONFIG.max_age)): The maximum number
   of days since a collection was last seen before it is removed from
   consideration.
3. `max_size` (default $(DEFAULT_INVENTORY_CONFIG.max_size)): The maximum
   (total) size of the store.
4. `recency_beta` (default $(DEFAULT_INVENTORY_CONFIG.recency_beta)): When
   removing items to avoid going over `max_size`, how much recency should be
   valued. Can be set to any value in (-∞, ∞). Larger (positive) values weight
   recency more, and negative values weight size more. -1 and 1 are equivalent.
"""

"""
Cache IO from data storage backends.

### Configuration

System-wide configuration can be set via the `store gc set` REPL command, or
directly modifying the `$(@__MODULE__).INVENTORY.config` struct.

$STORE_GC_CONFIG_INFO
"""
const STORE_PLUGIN = Plugin("store", [
    function (post::Function, f::typeof(storage), storer::DataStorage, as::Type; write::Bool)
        global INVENTORY
        # Get any applicable cache file
        update_inventory!()
        source = getsource(storer)
        file = storefile(storer)
        if !shouldstore(storer) || write
            # If the store is invalid (should not be stored, or about to be
            # written to), then it should be removed before proceeding as
            # normal.
            if !isnothing(source)
                index = findfirst(==(source), INVENTORY.stores)
                !isnothing(index) && deleteat!(INVENTORY.stores, index)
                write(INVENTORY)
            end
            (post, f, (storer, as), (; write))
        elseif !isnothing(file) && isfile(file)
            # If using a cache file, ensure the parent collection is registered
            # as a reference.
            update_source!(source, storer)
            if as === IO || as === IOStream
                if should_log_event("store", storer)
                    @info "Opening $as for $(sprint(show, storer.dataset.name)) from the store"
                end
                (post, identity, (open(file, "r"),))
            elseif as === FilePath
                (post, identity, (FilePath(file),))
            else
                (post, f, (storer, as), (; write))
            end
        elseif as == IO || as == IOStream
            # Try to get it as a file, because that avoids
            # some potential memory issues (e.g. large downloads
            # which exceed memory limits).
            tryfile = storage(storer, FilePath; write)
            if !isnothing(tryfile)
                io = open(storesave(storer, FilePath, tryfile), "r")
                (post, identity, (io,))
            else
                (post ∘ storesave(storer, as), f, (storer, as), (; write))
            end
        elseif as === FilePath
            (post ∘ storesave(storer, as), f, (storer, as), (; write))
        else
            (post, f, (storer, as), (; write))
        end
    end])

"""
Cache the results of data loaders using the `Serialisation` standard library. Cache keys
are determined by the loader "recipe" and the type requested.

It is important to note that not all data types can be cached effectively, such
as an `IOStream`.

## Configuration

Caching of individual loaders can be disabled by setting the "cache" parameter
to `false`, i.e.

```toml
[[somedata.loader]]
cache = false
...
```

System-wide configuration can be set via the `store gc set` REPL command, or
directly modifying the `$(@__MODULE__).INVENTORY.config` struct.

$STORE_GC_CONFIG_INFO
"""
const CACHE_PLUGIN = Plugin("cache", [
    function (post::Function, f::typeof(load), loader::DataLoader, source::Any, as::Type)
        if shouldstore(loader, as) && get(loader, "cache", true) === true
            # Get any applicable cache file
            update_inventory!()
            cache = getsource(loader, as)
            file = storefile(cache)
            # Ensure all needed packages are loaded, and all relevant
            # types have the same structure, before loading.
            if !isnothing(file)
                for pkg in cache.packages
                    DataToolkitBase.get_package(pkg)
                end
                if !all(@. rhash(typeify(first(cache.types))) == last(cache.types))
                    file = nothing
                end
            end
            if !isnothing(file) && isfile(file)
                if should_log_event("cache", loader)
                    @info "Loading $as form of $(sprint(show, loader.dataset.name)) from the store"
                end
                update_source!(cache, loader)
                info = Base.invokelatest(deserialize, file)
                (post, identity, (info,))
            else
                (post ∘ storesave(loader), f, (loader, source, as))
            end
        else
            (post, f, (loader, source, as))
        end
    end])
