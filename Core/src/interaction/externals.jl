"""
    loadcollection!(source::Union{<:AbstractString, <:IO}, mod::Module=Base.Main;
                    soft::Bool=false, index::Int=1)

Load a data collection from `source` and add it to the data stack at `index`.
`source` must be accepted by `read(source, DataCollection)`.

`mod` should be set to the Module within which `loadcollection!` is being
invoked. This is important when code is run by the collection. As such,
it is usually appropriate to call:

```julia
loadcollection!(source, @__MODULE__; soft)
```

When `soft` is set, should an data collection already exist with the same UUID,
nothing will be done and `nothing` will be returned.
"""
function loadcollection!(source::Union{<:AbstractString, <:IO}, mod::Module=Base.Main;
                         soft::Bool=false, index::Int=1)
    uuid = UUID(get(if source isa AbstractString
                        open(source, "r") do io TOML.parse(io) end
                    else
                        mark(source)
                        t = TOML.parse(source)
                        reset(source)
                        t
                    end, "uuid", uuid4()))
    existingpos = findfirst(c -> c.uuid == uuid, STACK)
    if !isnothing(existingpos)
        if soft
            return nothing
        else
            @warn "Data collection already existed on stack, replacing."
            deleteat!(STACK, existingpos)
        end
    end
    collection = read(source, DataCollection; mod)
    nameconflicts = filter(c -> c.name == collection.name, STACK)
    if !isempty(nameconflicts)
        printstyled(stderr, "!", color=:yellow, bold=true)
        print(stderr, " the data collection ")
        printstyled(stderr, collection.name, color=:green)
        print(stderr, " (UUID: ")
        printstyled(stderr, collection.uuid, color=:yellow)
        print(stderr, ")\n  conflicts with datasets already loaded with the exact same name:\n")
        for conflict in nameconflicts
            print(stderr, "  • ")
            printstyled(stderr, conflict.uuid, '\n', color=:yellow)
        end
        println(stderr, "  You must now refer to these datasets by their UUID to be unambiguous.")
    end
    insert!(STACK, clamp(index, 1, length(STACK)+1), collection)
    collection
end

"""
    dataset([collection::DataCollection], identstr::AbstractString, [parameters::Dict{String, Any}])
    dataset([collection::DataCollection], identstr::AbstractString, [parameters::Pair{String, Any}...])

Return the data set identified by `identstr`, optionally specifying the `collection`
the data set should be found in and any `parameters` that apply.
"""
dataset(identstr::AbstractString)::DataSet =
    resolve(identstr; resolvetype=false)
dataset(identstr::AbstractString, parameters::Dict{String, Any})::DataSet =
    resolve(identstr, parameters; resolvetype=false)

function dataset(identstr::AbstractString, kv::Pair{<:AbstractString, <:Any}, kvs::Pair{<:AbstractString, <:Any}...)
    parameters = newdict(String, Any, length(kvs) + 1)
    parameters[String(first(kv))] = last(kv)
    for (key, value) in kvs
        parameters[String(key)] = value
    end
    dataset(identstr, parameters)
end

function dataset(collection::DataCollection, identstr::AbstractString)
    ident = @advise collection parse_ident(identstr)::Identifier
    resolve(collection, ident; resolvetype=false)::DataSet
end

function dataset(collection::DataCollection, identstr::AbstractString, parameters::Dict{String, Any})
    ident = @advise collection parse_ident(identstr)::Identifier
    resolve(collection, Identifier(ident, parameters); resolvetype=false)::DataSet
end

"""
    read(filename::AbstractString, DataCollection; writer::Union{Function, Nothing})

Read the entire contents of a file as a `DataCollection`.

The default value of writer is `self -> write(filename, self)`.
"""
Base.read(f::AbstractString, ::Type{DataCollection}; mod::Module=Base.Main) =
    open(f, "r") do io read(io, DataCollection; path=abspath(f), mod) end

"""
    read(io::IO, DataCollection; path::Union{String, Nothing}=nothing, mod::Module=Base.Main)

Read the entirety of `io`, as a `DataCollection`.
"""
Base.read(io::IO, ::Type{DataCollection};
          path::Union{String, Nothing}=nothing, mod::Module=Base.Main) =
    DataCollection(TOML.parse(io); path, mod)

"""
    read(dataset::DataSet, as::Type)
    read(dataset::DataSet) # as default type

Obtain information from `dataset` in the form of `as`, with the appropriate
loader and storage provider automatically determined.

This executes the following component of the overall data flow:
```
                 ╭────loader─────╮
                 ╵               ▼
Storage ◀────▶ Data          Information
```

The loader and storage provider are selected by identifying the highest priority
loader that can be satisfied by a storage provider. What this looks like in practice
is illustrated in the diagram below.
```
      read(dataset, Matrix) ⟶ ::Matrix ◀╮
         ╭───╯        ╰────────────▷┬───╯
╔═════╸dataset╺══════════════════╗  │
║ STORAGE      LOADERS           ║  │
║ (⟶ File)─┬─╮ (File ⟶ String)   ║  │
║ (⟶ IO)   ┊ ╰─(File ⟶ Matrix)─┬─╫──╯
║ (⟶ File)┄╯   (IO ⟶ String)   ┊ ║
║              (IO ⟶ Matrix)╌╌╌╯ ║
╚════════════════════════════════╝

  ─ the load path used
  ┄ an option not taken
```

The types that a `DataSet` can be loaded as are determined by the `loaders`,
their declared types, and the implemented methods. If a method exists that can load
`dataset` to a subtype of `as`, it will be used. Methods that produce a type
declared in `dataset`'s `loaders` are preferred.
"""
function Base.read(dataset::DataSet, @nospecialize(as::Type))::as
    @log_do("read",
            "Reading $(dataset.name) as $as",
            @advise read1(dataset, as))
end

function Base.read(dataset::DataSet)
    as = nothing
    for qtype in getproperty.(dataset.loaders, :type) |> Iterators.flatten
        as = typeify(qtype, mod=dataset.collection.mod)
        isnothing(as) || break
    end
    if isnothing(as)
        possiblepkgs = getproperty.(getproperty.(dataset.loaders, :type) |> Iterators.flatten, :root)
        helpfulextra = if isempty(possiblepkgs)
            "There are no known types (from any packages) that this data set can be loaded as."
        else
            "You may have better luck with one of the following packages loaded: $(join(sort(unique(possiblepkgs)), ", "))"
        end
        throw(TransformerError(
            "Data set $(sprint(show, dataset.name)) could not be loaded in any form.\n $helpfulextra"))
    end
    read(dataset, as)
end

"""
    read1(dataset::DataSet, as::Type)

The advisable implementation of `read(dataset::DataSet, as::Type)`, which see.

This is essentially an exercise in useful indirection.
"""
function read1(dataset::DataSet, as::Type)::as
    for loader in dataset.loaders
        l_steps = typesteps(loader, as)
        isempty(l_steps) && continue
        # Find the highest priority load function that can be satisfied,
        # by going through each of the storage backends one at a time:
        # looking for the first that is (a) compatible with a load function,
        # and (b) available (checked via `!isnothing`).
        for storage in dataset.storage
            for (Tloader_in, Tloader_out) in l_steps
                s_steps = typesteps(storage, Tloader_in; write = false)
                for (_, Tstorage_out) in s_steps
                    datahandle = open(dataset, Tstorage_out; write = false)
                    if !isnothing(datahandle)
                        result = @advise dataset load(loader, datahandle, Tloader_out)
                        if !isnothing(result)
                            return something(result)
                        elseif datahandle isa IOStream
                            close(datahandle)
                        end
                    end
                end
            end
        end
        # Check for a "null storage" option. This is to enable loaders
        # like DataToolkitCommon's `:julia` which can construct information
        # without an explicit storage backend.
        for (Tloader_in, Tloader_out) in l_steps
            if Tloader_in == Nothing
                result = @advise dataset load(loader, nothing, as)
                !isnothing(result) && return something(result)
            end
        end
    end
    throw(guess_read_failure_cause(dataset, as))
end

function guess_read_failure_cause(dataset::DataSet, as::Type)
    loader_steps = [typesteps(loader, as) for loader in dataset.loaders] |> Iterators.flatten |> collect
    if all(isempty, loader_steps)
        UnsatisfyableTransformer(dataset, DataLoader, [QualifiedType(as)])
    else
        loader_intypes = map(QualifiedType, map(first, loader_steps) |> unique)
        UnsatisfyableTransformer(dataset, DataStorage, loader_intypes)
    end
end

function Base.read(ident::Identifier, as::Type)
    dataset = resolve(ident, resolvetype=false)
    read(dataset, as)
end

function Base.read(ident::Identifier)
    isnothing(ident.type) &&
        throw(ArgumentError("Cannot read from DataSet Identifier without type information."))
    mod = getlayer(ident.collection).mod
    read(ident, typeify(ident.type; mod))
end

"""
    load(loader::DataLoader{driver}, source::Any, as::Type)

Using a certain `loader`, obtain information in the form of
`as` from the data given by `source`.

This fulfils this component of the overall data flow:
```
  ╭────loader─────╮
  ╵               ▼
Data          Information
```

When the loader produces `nothing` this is taken to indicate that it was unable
to load the data for some reason, and that another loader should be tried if
possible. This can be considered a soft failure. Any other value is considered
valid information.
"""
function load end

load((loader, source, as)::Tuple{DataLoader, Any, Type}) =
    load(loader, source, as)

# A selection of fallback methods for various forms of raw file content

"""
    open(dataset::DataSet, as::Type; write::Bool=false)

Obtain the data of `dataset` in the form of `as`, with the appropriate storage
provider automatically selected.

A `write` flag is also provided, to help the driver pick a more appropriate form
of `as`.

This executes the following component of the overall data flow:
```
                 ╭────loader─────╮
                 ╵               ▼
Storage ◀────▶ Data          Information
```
"""
function Base.open(data::DataSet, as::Type; write::Bool=false)::Union{as, Nothing}
    for storage_provider in data.storage
        for (_, Tout) in typesteps(storage_provider, as; write)
            result = @advise data storage(storage_provider, Tout; write)
            if !isnothing(result)
                return something(result)
            end
        end
    end
end
# Base.open(data::DataSet, qas::QualifiedType; write::Bool) =
#     open(typeify(qas, mod=data.collection.mod), data; write)

"""
    storage(storer::DataStorage, as::Type; write::Bool=false)

Fetch the `as` from `storer`, appropiate for reading data from or writing data
to (depending on `write`).

By default, this just calls [`getstorage`](@ref) or [`putstorage`](@ref) (depending on `write`).

This executes the following component of the overall data flow:
```
Storage ◀────▶ Data
```
"""
function storage(storer::DataStorage, as::Type; write::Bool=false)
    if write
        putstorage(storer, as)
    else
        getstorage(storer, as)
    end
end

"""
    getstorage(storer::DataStorage, as::Type)

Fetch the `as` form of `storer`, for reading data from.

This executes the following component of the overall data flow:
```
Storage ─────▶ Data
```

See also: [`storage`](@ref), [`putstorage`](@ref).
"""
getstorage(::DataStorage, ::Any) = nothing

"""
    putstorage(storer::DataStorage, as::Type)

Fetch a handle in the form `as` from `storer`, that data can be written to.

This executes the following component of the overall data flow:
```
Storage ◀───── Data
```

See also: [`storage`](@ref), [`getstorage`](@ref).
"""
putstorage(::DataStorage, ::Any) = nothing

"""
    write(dataset::DataSet, info::Any)

TODO write docstring
"""
function Base.write(dataset::DataSet, info::T) where {T}
    all_write_fn_sigs = map(fn -> Base.unwrap_unionall(fn.sig),
                            methods(save, Tuple{DataWriter, Any, Any}))
    qtype = QualifiedType(T)
    # Filter to loaders which are declared in `dataset` as supporting `as`.
    # These will have already been orderd by priority during parsing.
    potential_writers =
        filter(writer -> any(st -> ⊆(qtype, st, mod=dataset.collection.mod), writer.type),
               dataset.writers)
    for writer in potential_writers
        write_fn_sigs = filter(fnsig -> issubtype(writer, fnsig.types[2]), all_write_fn_sigs)
        # Find the highest priority save function that can be satisfied,
        # by going through each of the storage backends one at a time:
        # looking for the first that is (a) compatible with a save function,
        # and (b) available (checked via `!isnothing`).
        for storage in dataset.storage
            for write_fn_sig in write_fn_sigs
                supported_storage_types = Vector{Type}(
                    filter(!isnothing, typeify.(storage.type)))
                valid_storage_types =
                    filter(stype -> issubtype(stype, write_fn_sig.types[3]),
                           supported_storage_types)
                for storage_type in valid_storage_types
                    datahandle = open(dataset, storage_type; write = true)
                    if !isnothing(datahandle)
                        res = @advise dataset save(writer, datahandle, info)
                        if res isa IO && isopen(res)
                            close(res)
                        end
                        return nothing
                    end
                end
            end
        end
    end
    if length(potential_writers) == 0
        throw(TransformerError("There are no writers for $(sprint(show, dataset.name)) that can work with $T"))
    else
        TransformerError("There are no available storage backends for $(sprint(show, dataset.name)) that can be used by a writer for $T.")
    end
end

"""
    save(writer::Datasaveer{driver}, destination::Any, information::Any)

Using a certain `writer`, save the `information` to the `destination`.

This fulfils this component of the overall data flow:
```
Data          Information
  ▲               ╷
  ╰────writer─────╯
```
"""
function save end

save((writer, dest, info)::Tuple{DataWriter, Any, Any}) =
    save(writer, dest, info)
