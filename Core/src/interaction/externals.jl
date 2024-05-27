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

dataset(collection::DataCollection, identstr::AbstractString) =
    resolve(collection, @advise collection parse_ident(identstr);
            resolvetype=false)::DataSet

function dataset(collection::DataCollection, identstr::AbstractString, parameters::Dict{String, Any})
    ident = @advise collection parse_ident(identstr)
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

This executes this component of the overall data flow:
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

TODO explain further
```
"""
function Base.read(dataset::DataSet, as::Type)::as
    @advise read1(dataset, as)
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
    @advise read1(dataset, as)
end

"""
    issubtype(X::Type, T::Union{Type, TypeVar})
    issubtype(x::X, T::Union{Type, TypeVar})

Check if `X` is indeed a subtype of `T`.

This is a tweaked version of `isa` that can (mostly) handle `TypeVar` instances.
"""
function issubtype(X::Type, T::Union{Type, TypeVar})
    if T isa TypeVar
        # We can't really handle complex `TypeVar` situations,
        # but we'll give the very most basic a shot, and cross
        # our fingers with the rest.
        if T.lb isa Type &&  T.ub isa Type
            T.lb <: X <: T.ub
        else
            false
        end
    else
        @assert T isa Type
        X <: T
    end
end

issubtype(x, T::Union{Type, TypeVar}) =
    issubtype(typeof(x), T::Union{Type, TypeVar})

"""
    isparamsubtype(X, T::Union{Type, TypeVar}, Tparam::Union{Type, TypeVar}, paramT::Type)

Check that `arg` is of type `T`, where `T` may be parameterised by
`Tparam` which itself takes on the type `paramT`.

More specifically, when `Tparam == Type{T}`, this checks that
`arg` is of type `paramT`, and returns `issubtype(arg, T)` otherwise.
"""
function isparamsubtype(X::Type, T::Union{Type, TypeVar}, Tparam::Union{Type, TypeVar}, paramT::Type)
    if T isa TypeVar && Type{T} == Tparam
        X <: paramT
    else
        issubtype(X, T)
    end
end

"""
    read1(dataset::DataSet, as::Type)

The advisible implementation of `read(dataset::DataSet, as::Type)`
This is essentially an excersise in useful indirection.
"""
function read1(dataset::DataSet, as::Type)
    all_load_fn_sigs = map(fn -> Base.unwrap_unionall(fn.sig),
                           methods(load, Tuple{DataLoader, Any, Any}))
    qtype = QualifiedType(as)
    # Filter to loaders which are declared in `dataset` as supporting `as`.
    # These will have already been ordered by priority during parsing.
    potential_loaders =
        filter(loader -> any(st -> ⊆(st, qtype, mod=dataset.collection.mod), loader.type),
               dataset.loaders)
    # If no matching loaders could be found, be a bit generous and /just try/
    # filtering to the specified `as` type. If this works, it's probably what's
    # wanted, and incompatibility should be caught by later stages.
    if isempty(potential_loaders)
        # Here I use `!isempty(methods(...))` which may seem strange, given
        # `hasmethod` exists. While in theory it would be reasonable to expect
        # that `hasmethod(f, Tuple{A, Union{}, B})` would return true if a method
        # with the signature `Tuple{A, <:Any, B}` existed, this is unfortunately
        # not the case in practice, and so we must resort to `methods`.
        potential_loaders =
            filter(loader -> !isempty(methods(load, Tuple{typeof(loader), <:Any, Type{as}})),
                   dataset.loaders)
    end
    for loader in potential_loaders
        load_fn_sigs = filter(fnsig -> issubtype(loader, fnsig.types[2]), all_load_fn_sigs)
        # Find the highest priority load function that can be satisfied,
        # by going through each of the storage backends one at a time:
        # looking for the first that is (a) compatible with a load function,
        # and (b) available (checked via `!isnothing`).
        for storage in dataset.storage
            for load_fn_sig in load_fn_sigs
                supported_storage_types = Vector{Type}(
                    filter(!isnothing, typeify.(storage.type)))
                valid_storage_types =
                    filter(stype -> isparamsubtype(stype, load_fn_sig.types[3], load_fn_sig.types[4], as),
                           supported_storage_types)
                for storage_type in valid_storage_types
                    datahandle = open(dataset, storage_type; write = false)
                    if !isnothing(datahandle)
                        result = @advise dataset load(loader, datahandle, as)
                        if !isnothing(result)
                            return something(result)
                        end
                    end
                end
            end
        end
        # Check for a "null storage" option. This is to enable loaders
        # like DataToolkitCommon's `:julia` which can construct information
        # without an explicit storage backend.
        for load_fn_sig in load_fn_sigs
            if load_fn_sig.types[3] == Nothing
                return @advise dataset load(loader, nothing, as)
            end
        end
    end
    if length(potential_loaders) == 0
        throw(UnsatisfyableTransformer(dataset, DataLoader, [qtype]))
    else
        loadertypes = map(
            f -> QualifiedType( # Repeat the logic from `valid_storage_types` / `isparamsubtype`
                if f.types[3] isa TypeVar
                    if f.types[4] == Type{f.types[3]}
                        as
                    else
                        f.types[3].ub
                    end
                else
                    f.types[3]
                end),
            filter(f -> any(l -> issubtype(l, f.types[2]), potential_loaders),
                   all_load_fn_sigs)) |> unique
        throw(UnsatisfyableTransformer(dataset, DataStorage, loadertypes))
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

"""
    open(dataset::DataSet, as::Type; write::Bool=false)

Obtain the data of `dataset` in the form of `as`, with the appropriate storage
provider automatically selected.

A `write` flag is also provided, to help the driver pick a more appropriate form
of `as`.

This executes this component of the overall data flow:
```
                 ╭────loader─────╮
                 ╵               ▼
Storage ◀────▶ Data          Information
```
"""
function Base.open(data::DataSet, as::Type; write::Bool=false)
    for storage_provider in data.storage
        if any(t -> ⊆(as, t, mod=data.collection.mod), storage_provider.type)
            result = @advise data storage(storage_provider, as; write)
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

Fetch a `storer` in form `as`, appropiate for reading from or writing to
(depending on `write`).

By default, this just calls `getstorage` or `putstorage` (when `write=true`).

This executes this component of the overall data flow:
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

getstorage(::DataStorage, ::Any) = nothing

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

# For use during parsing, see `fromspec` in `model/parser.jl`.

function extracttypes(T::Type)
    splitunions(T::Type) = if T isa Union Base.uniontypes(T) else (T,) end
    if T == Type || T == Any
        (Any,)
    elseif T isa UnionAll
        first(Base.unwrap_unionall(T).parameters).ub |> splitunions
    elseif T isa Union
        first.(getproperty.(Base.uniontypes(T), :parameters))
    else
        T1 = first(T.parameters)
        if T1 isa TypeVar T1.ub else T1 end |> splitunions
    end
end

const genericstore = first(methods(storage, Tuple{DataStorage{Any}, Any}))
const genericstoreget = first(methods(getstorage, Tuple{DataStorage{Any}, Any}))
const genericstoreput = first(methods(putstorage, Tuple{DataStorage{Any}, Any}))

supportedtypes(L::Type{<:DataLoader}, T::Type=Any)::Vector{QualifiedType} =
    map(fn -> extracttypes(Base.unwrap_unionall(fn.sig).types[4]),
        sort(methods(load, Tuple{L, T, Any}), by=m->m.primary_world)) |>
            Iterators.flatten .|> QualifiedType |> unique |> reverse

supportedtypes(W::Type{<:DataWriter}, T::Type=Any)::Vector{QualifiedType} =
    map(fn -> QualifiedType(Base.unwrap_unionall(fn.sig).types[4]),
        sort(methods(save, Tuple{W, T, Any}), by=m->m.primary_world)) |>
            unique |> reverse

supportedtypes(S::Type{<:DataStorage})::Vector{QualifiedType} =
    map(fn -> extracttypes(Base.unwrap_unionall(fn.sig).types[3]),
        let ms = filter(m -> m != genericstore,
                        sort(methods(storage, Tuple{S, Any}), by=m->m.primary_world))
            if isempty(ms)
                vcat(filter(m -> m != genericstoreget,
                            sort(methods(getstorage, Tuple{S, Any}), by=m->m.primary_world)),
                     filter(m -> m != genericstoreput,
                            sort(methods(putstorage, Tuple{S, Any}), by=m->m.primary_world)))
            else ms end
        end) |> Iterators.flatten .|> QualifiedType |> unique |> reverse
