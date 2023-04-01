struct DriverUnimplementedException <: Exception
    transform::AbstractDataTransformer
    driver::Symbol
    method::Symbol
end

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
    dataset([collection::DataCollection], identstr::AbstractString, [parameters::Pair{Symbol, Any}...])

Return the data set identified by `identstr`, optionally specifying the `collection`
the data set should be found in and any `parameters` that apply.
"""
dataset(identstr::AbstractString) = resolve(identstr; resolvetype=false)
dataset(identstr::AbstractString, parameters::Dict{String, Any}) =
    resolve(identstr, parameters; resolvetype=false)

function dataset(identstr::AbstractString, kv::Pair{Symbol, <:Any}, kvs::Pair{Symbol, <:Any}...)
    parameters = Dict{String, Any}()
    parameters[String(first(kv))] = last(kv)
    for (key, value) in kvs
        parameters[String(key)] = value
    end
    dataset(identstr, parameters)
end

dataset(collection::DataCollection, identstr::AbstractString) =
    resolve(collection, @advise parse(Identifier, identstr);
            resolvetype=false)

function dataset(collection::DataCollection, identstr::AbstractString, parameters::Dict{String, Any})
    ident = @advise parse(Identifier, identstr)
    resolve(collection, Identifier(ident, parameters); resolvetype=false)
end

function dataset(collection::DataCollection, identstr::AbstractString, kv::Pair{Symbol, <:Any}, kvs::Pair{Symbol, <:Any}...)
    parameters = Dict{String, Any}()
    parameters[String(first(kv))] = last(kv)
    for (key, value) in kvs
        parameters[String(key)] = value
    end
    dataset(collection, identstr, parameters)
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

Read the entirity of `io`, as a `DataCollection`.
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
loader that can be saisfied by a storage provider. What this looks like in practice
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
function Base.read(dataset::DataSet, as::Type)
    @advise _read(dataset, as)
end
function Base.read(dataset::DataSet)
    as = nothing
    for qtype in getproperty.(dataset.loaders, :type) |> Iterators.flatten
        as = typeify(qtype, mod=dataset.collection.mod)
        isnothing(as) || break
    end
    isnothing(as) && error("Data set '$(dataset.name)' could not be loaded in any form.")
    @advise _read(dataset, as)
end

"""
    _read(dataset::DataSet, as::Type)

The advisible implementation of `read(dataset::DataSet, as::Type)`
This is essentially an excersise in useful indirection.
"""
function _read(dataset::DataSet, as::Type)
    all_load_fn_sigs = map(fn -> Base.unwrap_unionall(fn.sig),
                             methods(load, Tuple{DataLoader, Any, Any}))
    qtype = QualifiedType(as)
    # Filter to loaders which are declared in `dataset` as supporting `as`.
    # These will have already been ordered by priority during parsing.
    potential_loaders =
        filter(loader -> any(st -> ⊆(st, qtype, mod=dataset.collection.mod), loader.type),
               dataset.loaders)
    for loader in potential_loaders
        load_fn_sigs = filter(fnsig -> loader isa fnsig.types[2], all_load_fn_sigs)
        # Find the highest priority load function that can be satisfied,
        # by going through each of the storage backends one at a time:
        # looking for the first that is (a) compatable with a load function,
        # and (b) availible (checked via `!isnothing`).
        for storage in dataset.storage
            for load_fn_sig in load_fn_sigs
                supported_storage_types = Vector{Type}(
                    filter(!isnothing, typeify.(storage.type)))
                valid_storage_types =
                    filter(stype -> let accept = load_fn_sig.types[3]
                               if accept isa TypeVar
                                   accept.lb <: stype <: accept.ub
                               else # must be a Type
                                   stype <: accept
                               end
                           end,
                           supported_storage_types)
                for storage_type in valid_storage_types
                    datahandle = open(dataset, storage_type; write = false)
                    if !isnothing(datahandle)
                        result = @advise dataset load(loader, datahandle, as)
                        if !isnothing(result)
                            return result
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
    # TODO non-generic error type
    if length(potential_loaders) == 0
        throw(error("There are no loaders for '$(dataset.name)' that can provide $as"))
    else
        throw(error("There are no availible storage backends for '$(dataset.name)' that can be used by a loader for $as."))
    end
end

function Base.read(ident::Identifier, as::Type)
    dataset = resolve(ident)
    read(dataset, as)
end

function Base.read(ident::Identifier)
    if isnothing(ident.type)
        throw(ArgumentError("Cannot read from DataSet Identifier without type information."))
    end
    read(ident, if !isnothing(ident.type)
             mod = getlayer(ident.collection).mod
             typeify(ident.type; mod)
         end)
end

"""
    load(loader::DataLoader{driver}, source::Any, as::Type)

Using a certain `loader`, obtain information in the form of
`as` from the data given by `source`.

This fufills this component of the overall data flow:
```
  ╭────loader─────╮
  ╵               ▼
Data          Information
```

When the loader produces `nothing` this is taken to indicate that it was unable
to load the data for some reason, and that another loader should be tried if
possible. This can be considered a soft failiure. Any other value is considered
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
                return result
            end
        end
    end
end
# Base.open(data::DataSet, qas::QualifiedType; write::Bool) =
#     open(typeify(qas, mod=data.collection.mod), data; write)

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
        write_fn_sigs = filter(fnsig -> writer isa fnsig.types[2], all_write_fn_sigs)
        # Find the highest priority load function that can be satisfied,
        # by going through each of the storage backends one at a time:
        # looking for the first that is (a) compatable with a load function,
        # and (b) availible (checked via `!isnothing`).
        for storage in dataset.storage
            for write_fn_sig in write_fn_sigs
                supported_storage_types = Vector{Type}(
                    filter(!isnothing, typeify.(storage.type)))
                valid_storage_types =
                    filter(stype -> stype <: write_fn_sig.types[3],
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
        error("There are no writers for '$(dataset.name)' that can work with $T")
    else
        error("There are no availible storage backends for '$(dataset.name)' that can be used by a writer for $T.")
    end
end

"""
    save(writer::Datasaveer{driver}, destination::Any, information::Any)

Using a certain `writer`, save the `information` to the `destination`.

This fufills this component of the overall data flow:
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
        methods(load, Tuple{L, T, Any})) |>
            Iterators.flatten .|> QualifiedType |> unique |> reverse

supportedtypes(W::Type{<:DataWriter}, T::Type=Any)::Vector{QualifiedType} =
    map(fn -> QualifiedType(Base.unwrap_unionall(fn.sig).types[3]),
        methods(save, Tuple{W, T, Any})) |> unique |> reverse

supportedtypes(S::Type{<:DataStorage})::Vector{QualifiedType} =
    map(fn -> extracttypes(Base.unwrap_unionall(fn.sig).types[3]),
        let ms = filter(m -> m != genericstore, methods(storage, Tuple{S, Any}))
            if isempty(ms)
                vcat(filter(m -> m != genericstoreget,
                            methods(getstorage, Tuple{S, Any})),
                     filter(m -> m != genericstoreput,
                        methods(putstorage, Tuple{S, Any})))
            else ms end
        end) |> Iterators.flatten .|> QualifiedType |> unique |> reverse
