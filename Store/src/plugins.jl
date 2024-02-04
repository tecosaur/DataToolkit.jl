const STORE_GC_CONFIG_INFO = md"""
A few (system-wide) settings determine garbage collection behaviour:
- `auto_gc` (default $(DEFAULT_INVENTORY_CONFIG.auto_gc)): How often to
  automatically run garbage collection (in hours). Set to a non-positive value
  to disable.
- `max_age` (default $(DEFAULT_INVENTORY_CONFIG.max_age)): The maximum number
  of days since a collection was last seen before it is removed from
  consideration.
- `max_size` (default $(DEFAULT_INVENTORY_CONFIG.max_size)): The maximum
  (total) size of the store.
- `recency_beta` (default $(DEFAULT_INVENTORY_CONFIG.recency_beta)): When
  removing items to avoid going over `max_size`, how much recency should be
  valued. Can be set to any value in (-∞, ∞). Larger (positive) values weight
  recency more, and negative values weight size more. -1 and 1 are equivalent.
- `store_dir` (default $(DEFAULT_INVENTORY_CONFIG.store_dir)): The directory
  (either as an absolute path, or relative to the inventory file) that should be
  used for storage (IO) cache files.
- `cache_dir` (default $(DEFAULT_INVENTORY_CONFIG.cache_dir)): The directory
  (either as an absolute path, or relative to the inventory file) that should be
  used for Julia cache files.
"""

"""
Cache IO from data storage backends, by saving the contents to the disk.

## Configuration

#### Store path

The directory the the store is maintained in can be set via the `store.path`
configuration parameter.

```toml
config.store.path = "relative/to/datatoml"
```

The system default is `$(Base.Filesystem.contractuser(Store.BaseDirs.User.cache(Store.BaseDirs.Project("DataToolkit"))))`,
which can be overriden with the `DATATOOLKIT_STORE` environment variable.

#### Disabling on a per-storage basis

Saving of individual storage sources can be disabled by setting the "save"
parameter to `false`, i.e.

```toml
[[somedata.storage]]
save = false
```

#### Checksums

To ensure data integrity, a checksum can be specified, and checked when saving
to the store. For example,

```toml
[[iris.storage]]
checksum = "k12:cfb9a6a302f58e5a9b0c815bb7e8efb4"
```

If you do not have a checksum, but wish for one to be calculated upon accessing
the data, the checksum parameter can be set to the special value `"auto"`. When
the data is first accessed, a checksum will be generated and replace the "auto"
value.

Instead of `"auto"`, a particular checksum algorithm can be specified, by naming
it, e.g. `"sha256"`. The currently supported algorithms are: `k12` (Kangaroo
Twelve), `sha512`, `sha384`, `sha256`, `sha224`, `sha1`, `md5`, and `crc32c`.

To explicitly specify no checksum, set the parameter to `false`.

For data sets with `lifetime` set (see *Expiry/Lifecycle*), `"auto"` interpreted
as `false`.

#### Expiry/Lifecycle

After a storage source is saved, the cache file can be made to expire after a
certain period. This is done by setting the "`lifetime`" parameter of the storage,
i.e.

```toml
[[updatingdata.storage]]
lifetime = "3 days"
```

The lifetime parameter accepts a few formats, namely:

**ISO8061 periods** (with whole numbers only), both forms
1. `P[n]Y[n]M[n]DT[n]H[n]M[n]S`, e.g.
   - `P3Y6M4DT12H30M5S` represents a duration of "3 years, 6 months, 4 days,
     12 hours, 30 minutes, and 5 seconds"
   - `P23DT23H` represents a duration of "23 days, 23 hours"
   - `P4Y` represents a duration of "4 years"
2. `PYYYYMMDDThhmmss` / `P[YYYY]-[MM]-[DD]T[hh]:[mm]:[ss]`, e.g.
   - `P0003-06-04T12:30:05`
   - `P00030604T123005`

**"Prose style" period strings**, which are a repeated pattern of `[number] [unit]`,
where `unit` matches `year|y|month|week|wk|w|day|d|hour|h|minute|min|second|sec|`
optionally followed by an "s", comma, or whitespace. E.g.

- `3 years 6 months 4 days 12 hours 30 minutes 5 seconds`
- `23 days, 23 hours`
- `4d12h`

By default, the first lifetime period begins at the Unix epoch. This means a
daily lifetime will tick over at `00:00 UTC`. The "`lifetime_offset`" parameter
can be used to shift this. It can be set to a lifetime string, date/time-stamp,
or number of seconds.

For example, to have the lifetime expire at `03:00 UTC` instead, the lifetime
offset could be set to three hours.

```toml
[[updatingdata.storage]]
lifetime = "1 day"
lifetime_offset = "3h"
```

We can produce the same effect by specifying a different reference point for the
lifetime.

```toml
[[updatingdata.storage]]
lifetime = "1 day"
lifetime_offset = 1970-01-01T03:00:00
```

#### Store management

System-wide configuration can be set via the `store config set` REPL command, or
directly modifying the `$(@__MODULE__).getinventory().config` struct.

$STORE_GC_CONFIG_INFO
"""
const STORE_PLUGIN = Plugin("store", [
    function (f::typeof(storage), @nospecialize(storer::DataStorage), as::Type; write::Bool)
        inventory = getinventory(storer.dataset.collection) |> update_inventory!
        # Get any applicable cache file
        source = getsource(inventory, storer)
        file = storefile(inventory, storer)
        if !isnothing(file) && isfile(file) && haskey(storer.parameters, "lifetime")
            if epoch(storer) > epoch(storer, ctime(file))
                rm(file, force=true)
            end
        end
        if !(shouldstore(storer) || @getparam(storer."save"::Bool, false) === true) || write
            # If the store is invalid (should not be stored, or about to be
            # written to), then it should be removed before proceeding as
            # normal.
            if !isnothing(source) && inventory.file.writable
                index = findfirst(==(source), inventory.stores)
                !isnothing(index) && deleteat!(inventory.stores, index)
                Base.write(inventory)
            end
            (f, (storer, as), (; write))
        elseif !isnothing(file) && isfile(file)
            # If using a cache file, ensure the parent collection is registered
            # as a reference.
            update_source!(inventory, source, storer.dataset.collection)
            if as === IO || as === IOStream
                should_log_event("store", storer) &&
                    @info "Opening $as for $(sprint(show, storer.dataset.name)) from the store"
                (identity, (open(file, "r"),))
            elseif as === FilePath
                should_log_event("store", storer) &&
                    @info "Opening $as for $(sprint(show, storer.dataset.name)) from the store"
                (identity, (FilePath(file),))
            elseif as === Vector{UInt8}
                should_log_event("store", storer) &&
                    @info "Opening $as for $(sprint(show, storer.dataset.name)) from the store"
                (identity, (read(file),))
            elseif as === String
                should_log_event("store", storer) &&
                    @info "Opening $as for $(sprint(show, storer.dataset.name)) from the store"
                (identity, (read(file, String),))
            else
                (f, (storer, as), (; write))
            end
        elseif as === FilePath
            (storesave(inventory, storer, as), f, (storer, as), (; write))
        elseif as ∈ (IO, IOStream, Vector{UInt8}, String)
            # Try to get it as a file, because that avoids
            # some potential memory issues (e.g. large downloads
            # which exceed memory limits).
            tryfile = storage(storer, FilePath; write)
            if !isnothing(tryfile)
                io = open(storesave(inventory, storer, FilePath, tryfile).path, "r")
                (identity, (if as ∈ (IO, IOStream)
                                io
                            elseif as == Vector{UInt8}
                                read(io)
                            elseif as == String
                                read(io, String)
                            end,))
            else
                (storesave(inventory, storer, as), f, (storer, as), (; write))
            end
        else
            (f, (storer, as), (; write))
        end
    end,
    function (f::typeof(rhash), @nospecialize(storage::DataStorage), parameters::SmallDict, h::UInt)
        delete!(parameters, "save") # Does not impact the final result
        if haskey(parameters, "lifetime")
            delete!(parameters, "lifetime") # Does not impact the final result
            parameters["__epoch"] = epoch(storage)
        end
        (f, (storage, parameters, h))
    end,
    function (f::typeof(DataToolkitBase.init), dc::DataCollection)
        if "defaults" in dc.plugins && isinteractive() &&
            confirm_yn(" Use checksums by default?", true)
            dc = DataToolkitBase.config_set(
                dc, ["defaults", "storage", "_", "checksum"], "auto";
                quiet = true)
        end
        (f, (dc,))
    end,
    function (f::typeof(show_extra), io::IO, dataset::DataSet)
        if any(shouldstore, dataset.storage)
            print(io, "  Stored:  ")
            inventory = getinventory(dataset.collection) |> update_inventory!
            files = map(s -> if shouldstore(s) storefile(inventory, s) end,
                        dataset.storage)
            filter!(!isnothing, files)
            filter!(isfile, files)
            if isempty(files)
                printstyled(io, "no", color=:yellow)
            else
                printstyled("yes", color=:green)
                if length(files) > 1
                    printstyled('(', length(files), ')', color=:green)
                end
                print(' ', join(humansize(sum(filesize, files)), ' '))
            end
            print(io, '\n')
        end
        (f, (io, dataset))
    end])

"""
Cache the results of data loaders using the `Serialisation` standard library. Cache keys
are determined by the loader "recipe" and the type requested.

It is important to note that not all data types can be cached effectively, such
as an `IOStream`.

## Recipe hashing

The driver, parameters, type(s), of a loader and the storage drivers of a dataset
are all combined into the "recipe hash" of a loader.

```
╭─────────╮             ╭──────╮
│ Storage │             │ Type │
╰───┬─────╯             ╰───┬──╯
    │    ╭╌╌╌╌╌╌╌╌╌╮    ╭───┴────╮ ╭────────╮
    ├╌╌╌╌┤ DataSet ├╌╌╌╌┤ Loader ├─┤ Driver │
    │    ╰╌╌╌╌╌╌╌╌╌╯    ╰───┬────╯ ╰────────╯
╭───┴─────╮             ╭───┴───────╮
│ Storage ├─╼           │ Parmeters ├─╼
╰─────┬───╯             ╰───────┬───╯
      ╽                         ╽
```

Since the parameters of the loader (and each storage backend) can reference
other data sets (indicated with `╼` and `╽`), this hash is computed recursively,
forming a Merkle Tree. In this manner the entire "recipe" leading to the final
result is hashed.

```
                ╭───╮
                │ E │
        ╭───╮   ╰─┬─╯
        │ B ├──▶──┤
╭───╮   ╰─┬─╯   ╭─┴─╮
│ A ├──▶──┤     │ D │
╰───╯   ╭─┴─╮   ╰───╯
        │ C ├──▶──┐
        ╰───╯   ╭─┴─╮
                │ D │
                ╰───╯
```

In this example, the hash for a loader of data set "A" relies on the data sets
"B" and "C", and so their hashes are calculated and included. "D" is required by
both "B" and "C", and so is included in each. "E" is also used in "D".

## Configuration

#### Store path

This uses the same `store.path` configuration variable as the `store` plugin
(which see).

#### Disabling on a per-loader basis

Caching of individual loaders can be disabled by setting the "cache" parameter
to `false`, i.e.

```toml
[[somedata.loader]]
cache = false
...
```

#### Store management

System-wide configuration can be set via the `store config set` REPL command, or
directly modifying the `$(@__MODULE__).getinventory().config` struct.

$STORE_GC_CONFIG_INFO
"""
const CACHE_PLUGIN = Plugin("cache", [
    function (f::typeof(load), @nospecialize(loader::DataLoader), source::Any, as::Type)
        if shouldstore(loader, as) || @getparam(loader."cache"::Bool, false) === true
            # Get any applicable cache file
            inventory = getinventory(loader.dataset.collection) |> update_inventory!
            cache = getsource(inventory, loader, as)
            file = storefile(inventory, cache)
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
                    ds_name = sprint(io -> show(
                        io, MIME("text/plain"), Identifier(loader.dataset);
                        collection=loader.dataset.collection))
                    @info "Loading $as form of $(ds_name) from the store"
                end
                update_source!(inventory, cache, loader.dataset.collection)
                info = Base.invokelatest(deserialize, file)
                (identity, (info,))
            else
                (storesave(inventory, loader), f, (loader, source, as))
            end
        else
            (f, (loader, source, as))
        end
    end,
    function (f::typeof(rhash), @nospecialize(loader::DataLoader), parameters::SmallDict, h::UInt)
        delete!(parameters, "cache") # Does not impact the final result
        (f, (loader, parameters, h))
    end,
    function (f::typeof(show_extra), io::IO, dataset::DataSet)
        forms = [(s, t) for s in dataset.loaders for t in typeify.(s.type)
                     if !isnothing(t)]
        filter!(Base.splat(shouldstore), forms)
        if !isempty(forms)
            print(io, "  Cached:  ")
            inventory = getinventory(dataset.collection) |> update_inventory!
            files = map(((s, t),) -> storefile(inventory, getsource(inventory, s, t)),
                        forms)
            filter!(!isnothing, files)
            filter!(isfile, files)
            if isempty(files)
                printstyled(io, "no", color=:yellow)
            else
                printstyled("yes", color=:green)
                if length(files) > 1
                    printstyled('(', length(files), ')', color=:green)
                end
                print(' ', join(humansize(sum(filesize, files)), ' '))
            end
            print(io, '\n')
        end
        (f, (io, dataset))
    end])
