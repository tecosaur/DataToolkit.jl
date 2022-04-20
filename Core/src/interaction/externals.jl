struct DriverUnimplementedException <: Exception
    transform::AbstractDataTransformer
    driver::Symbol
    method::Symbol
end

"""
    loadcollection!(source::Any)
TODO write docstring
"""
function loadcollection!(source::Any)
    collection = read(source, DataCollection)
    existingpos = findfirst(c -> c.uuid == collection.uuid, STACK)
    if !isnothing(existingpos)
        deleteat!(STACK, existingpos)
    end
    pushfirst!(STACK, collection)
    nothing
end

"""
    read(filename::AbstractString, DataCollection; writer::Union{Function, Nothing})
Read the entire contents of a file as a `DataCollection`.

The default value of writer is `self -> write(filename, self)`.
"""
Base.read(f::AbstractString, ::Type{DataCollection}) =
    read(open(f, "r"), DataCollection; path=abspath(f))

"""
    read(io::IO, DataCollection; writer::Union{Function, Nothing}=nothing)

Read the entirity of `io`, as a `DataCollection`.
"""
Base.read(io::IO, ::Type{DataCollection}; path::Union{String, Nothing}=nothing) =
    DataCollection(TOML.parse(io); path)

"""
    read(dataset::DataSet, as::Type)
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
    all_load_functions = methods(load, Tuple{DataLoader, Any, Any})
    qtype = QualifiedType(as)
    potential_loaders = filter(loader -> qtype in loader.supports, dataset.loaders)
    for loader in potential_loaders
        load_functions =
            filter(l -> loader isa Base.unwrap_unionall(l.sig).types[2],
                   all_load_functions)
        for storage in dataset.storage
            for load_func in load_functions
                load_func_sig = Base.unwrap_unionall(load_func.sig)
                validstoragetypes = filter(stype -> stype <: load_func_sig.types[3],
                                           convert.(Type, storage.supports))
                for storage_type in validstoragetypes
                    datahandle = open(dataset, storage_type; write = false)
                    if !isnothing(datahandle)
                        return dataset.collection.advise(
                            load, loader, datahandle, as)
                    end
                end
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
    read(ident, convert(Type, ident.type))
end

function dataset(ident_str::AbstractString, parameters::Dict{String, Any})
    ident = Identifier(ident_str, parameters)
    resolve(ident)
end

dataset(ident_str::AbstractString; kwparams...) =
    dataset(ident_str, Dict{String, Any}(String(k) => v for (k, v) in kwparams))

function dataset(collection::DataCollection, ident_str::AbstractString, parameters::Dict{String, Any})
    ident = Identifier(ident_str, parameters)
    resolve(collection, ident)
end

dataset(collection::DataCollection, ident_str::AbstractString; kwparams...) =
    dataset(collection, ident_str,
            Dict{String, Any}(String(k) => v for (k, v) in kwparams))

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
"""
function load(::DataLoader{driver}, ::S, as::Type) where {driver, S, T}
    # TODO use non-generic error
    throw(error("No $driver loader which can produce $as from $S is defined"))
end
load((loader, source, as)::Tuple{DataLoader, Any, Type}) =
    load(loader, source, as)

"""
    open(dataset::DataSet, as::Type)
Obtain the data of `dataset` in the form of `as`, with the appropriate storage
provider automatically selected.

This executes this component of the overall data flow:
```
                 ╭────loader─────╮
                 ╵               ▼
Storage ◀────▶ Data          Information
```
"""
function Base.open(data::DataSet, as::Type; write::Bool=false)
    qtype = QualifiedType(as)
    for storage_provider in data.storage
        if qtype in storage_provider.supports
            return data.collection.advise(
                storage, storage_provider, as; write)
        end
    end
end
# Base.open(data::DataSet, qas::QualifiedType; write::Bool) =
#     open(convert(Type, qas), data; write)

function storage(storer::DataStorage, as::Type; write::Bool=false)
    if write
        putstorage(storer, as)
    else
        getstorage(storer, as)
    end
end

function getstorage(::DataStorage{driver}, ::T) where {driver, T}
    throw(error("No $driver storage reader is defined for $T"))
end

function putstorage(::DataStorage{driver}, ::T) where {driver, T}
    throw(error("No $driver storage writer is defined for $T"))
end

"""
    write(dataset::DataSet, info::Any)
TODO write docstring
"""
function Base.write(dataset::DataSet, info::T) where {T}
    all_write_functions = methods(writeinfo, Tuple{DataWriter, Any, Any})
    qtype = QualifiedType(T)
    potential_writers =
        filter(writer -> any(st -> qtype ⊆ st, writer.supports), dataset.writers)
    for writer in potential_writers
        write_functions =
            filter(l -> writer isa Base.unwrap_unionall(l.sig).types[2],
                   all_write_functions)
        for storage in dataset.storage
            for write_func in write_functions
                write_func_sig = Base.unwrap_unionall(write_func.sig)
                validstoragetypes = filter(stype -> stype <: write_func_sig.types[3],
                                           convert.(Type, storage.supports))
                for storage_type in validstoragetypes
                    datahandle = open(dataset, storage_type; write = true)
                    if !isnothing(datahandle)
                        return dataset.collection.advise(
                            writeinfo, writer, datahandle, info)
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

function writeinfo(::DataWriter{driver}, ::D, ::T) where {driver, D, T}
    error("No $driver to write a $T to a $D is defined")
end
writeinfo((writer, dest, info)::Tuple{DataWriter, Any, Any}) =
    writeinfo(writer, dest, info)
