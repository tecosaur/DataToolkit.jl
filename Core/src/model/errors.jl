abstract type IdentifierException <: Exception end

"""
    UnresolveableIdentifier{T}(identifier::Union{String, UUID}, [collection::DataCollection])

No `T` (opionally from `collection`) could be found that matches `identifier`.

# Example occurances

```julia-repl
julia> d"iirs"
ERROR: UnresolveableIdentifier: "iirs" does not match any known data sets
  Did you perhaps mean to refer to one of these data sets?
    ■:iris (75% match)
Stacktrace: [...]

julia> d"iris::Int"
ERROR: UnresolveableIdentifier: "iris::Int" does not match any known data sets
  Without the type restriction, however, the following data sets match:
    datatest:iris, which is availible as a DataFrame, Matrix, CSV.File
Stacktrace: [...]
```
"""
struct UnresolveableIdentifier{T, I} <: IdentifierException where {T, I <: Union{String, UUID}}
    identifier::I
    collection::Union{DataCollection, Nothing}
end

UnresolveableIdentifier{T}(ident::I, collection::Union{DataCollection, Nothing}=nothing) where {T, I <: Union{String, UUID}} =
    UnresolveableIdentifier{T, I}(ident, collection)

function Base.showerror(io::IO, err::UnresolveableIdentifier{DataSet, String})
    print(io, "UnresolveableIdentifier: ", sprint(show, err.identifier),
          " does not match any known data sets")
    if !isnothing(err.collection)
        print(io, " in ", sprint(show, err.collection.name))
    end
    # Check to see if there are any matches without the
    # type restriction (if applicable).
    notypematches = Vector{DataSet}()
    if err.identifier isa String
        if !isnothing(err.collection)
            ident = @advise err.collection parse(Identifier, err.identifier)
            if !isnothing(ident.type)
                identnotype = Identifier(ident.collection, ident.dataset,
                                         nothing, ident.parameters)
                notypematches = refine(
                    err.collection, err.collection.datasets, identnotype)
            end
        else
            for collection in STACK
                ident = @advise collection parse(Identifier, err.identifier)
                if !isnothing(ident.type)
                    identnotype = Identifier(ident.collection, ident.dataset,
                                             nothing, ident.parameters)
                    append!(notypematches, refine(
                        collection, collection.datasets, identnotype))
                end
            end
        end
    end
    # If there are any no-type matches then display them,
    # otherwise look for data sets with similar names.
    if !isempty(notypematches)
        print(io, "\n  Without the type restriction, however, the following data sets match:")
        for dataset in notypematches
            print(io, "\n    ")
            show(io, MIME("text/plain"), Identifier(dataset); dataset.collection)
            print(io, ", which is availible as a ")
            types = getfield.(dataset.loaders, :type) |> Iterators.flatten |> unique
            for type in types
                printstyled(io, string(type), color=:yellow)
                type === last(types) || print(io, ", ")
            end
        end
    else
        candidates = Tuple{Identifier, DataCollection, Float64}[]
        let collection = @something(err.collection, first(STACK))
            for ident in Identifier.(collection.datasets, nothing)
                istr = @advise collection string(ident)
                push!(candidates,
                    (ident, collection, stringsimilarity(err.identifier, istr)))
            end
        end
        if isnothing(err.collection) && !isempty(STACK)
            for collection in last(Iterators.peel(STACK))
                for ident in Identifier.(collection.datasets)
                    istr = @advise collection string(ident)
                    push!(candidates,
                        (ident, collection, stringsimilarity(err.identifier, istr)))
                end
            end
        end
        maxsimilarity = maximum(last.(candidates), init=0.0)
        if maxsimilarity >= 0.2
            print(io, "\n  Did you perhaps mean to refer to one of these data sets?")
            threshold = maxsimilarity * 0.9
            for (ident, collection, sim) in sort(candidates[last.(candidates) .>= threshold],
                                                by=last, rev=true)
                print(io, "\n    ")
                irep = IOContext(IOBuffer(), :color => true)
                show(irep, MIME("text/plain"), ident; collection)
                highlight_lcs(io, String(take!(irep.io)), err.identifier,
                              before="\e[2m", invert=true)
                printstyled(io, " (", round(Int, 100*sim), "% match)",
                            color=:light_black)
            end
        end
    end
end

function Base.showerror(io::IO, err::UnresolveableIdentifier{DataCollection})
    print(io, "UnresolveableCollection: No collections within the stack matched the ",
          ifelse(err.identifier isa UUID, "identifier ", "name "), string(err.identifier))
    if err.identifier isa String
        candidates = Tuple{DataCollection, Float64}[]
        for collection in STACK
            if !isnothing(collection.name)
                push!(candidates,
                      (collection, stringsimilarity(err.identifier, collection.name)))
            end
        end
        if maximum(last.(candidates), init=0.0) >= 0.5
            print(io, "\n  Did you perhaps mean to refer to one of these data collections?")
            for (collection, simiarity) in candidates
                print(io, "\n  • ")
                crep = IOContext(IOBuffer(), :color => true, :compact => true)
                show(crep, MIME("text/plain"), collection)
                highlight_lcs(io, String(take!(crep.io)), err.identifier,
                              before="\e[2m", invert=true)
                printstyled(io, " (", round(Int, 100*simiarity), "% similaity)",
                            color=:light_black)
            end
        end
    end
end

"""
    AmbiguousIdentifier(identifier::Union{String, UUID}, matches::Vector, [collection])

Searching for `identifier` (optionally within `collection`), found multiple
matches (provided as `matches`).

# Example occurance

```julia-repl
julia> d"multimatch"
ERROR: AmbiguousIdentifier: "multimatch" matches multiple data sets
    ■:multimatch [45685f5f-e6ff-4418-aaf6-084b847236a8]
    ■:multimatch [92be4bda-55e9-4317-aff4-8d52ee6a5f2c]
Stacktrace: [...]
```
"""
struct AmbiguousIdentifier{T, I} <: IdentifierException where {T, I <: Union{String, UUID}}
    identifier::I
    matches::Vector{T}
    collection::Union{DataCollection, Nothing}
end

AmbiguousIdentifier(identifier::Union{String, UUID}, matches::Vector{T}) where {T} =
    AmbiguousIdentifier{T}(identifier, matches, nothing)

function Base.showerror(io::IO, err::AmbiguousIdentifier{DataSet, I}) where {I}
    print(io, "AmbiguousIdentifier: ", sprint(show, err.identifier),
          " matches multiple data sets")
    if I == String
        for dataset in err.matches
            ident = Identifier(dataset, ifelse(err.collection === dataset.collection,
                                            nothing, :name))
            print(io, "\n    ")
            show(io, MIME("text/plain"), ident; collection=dataset.collection)
            printstyled(io, " [", dataset.uuid, ']', color=:light_black)
        end
    else
        print(io, ". There is likely some kind of accidental ID duplication occuring.")
    end
end

function Base.showerror(io::IO, err::AmbiguousIdentifier{DataCollection})
    print(io, "AmbiguousIdentifier: ", sprint(show, err.identifier),
          " matches multiple data collections in the stack")
    if I == String
        for collection in err.matches
            print(io, "\n  • ")
            printstyled(io, collection.name, color=:magenta)
            printstyled(io, " [", collection.uuid, "]", color=:light_magenta)
        end
        print(io, "\n  Consider referring to the data collection by UUID instead of name.")
    else
        print(io, ". Have you loaded the same data collection twice?")
    end
end

abstract type PackageException <: Exception end

"""
    UnregisteredPackage(name::Symbol, mod::Module)

The package `name` was asked for within `mod`, but has not been
registered by `mod`, and so cannot be loaded.

# Example occurance

```julia-repl
julia> @import Foo
ERROR: UnregisteredPackage: Foo has not been registered by Main, see @addpkg for more information
Stacktrace: [...]
```
"""
struct UnregisteredPackage <: PackageException
    name::Symbol
    mod::Module
end

function Base.showerror(io::IO, err::UnregisteredPackage)
    print(io, "UnregisteredPackage: ", err.name,
          " has not been registered by ", err.mod,
          ", see @addpkg for more information")
end

"""
    MissingPackage(pkg::Base.PkgId)

The package `pkg` was asked for, but does not seem to be availible in the
current environment.

# Example occurance

```julia-repl
julia> @addpkg Bar "00000000-0000-0000-0000-000000000000"
Bar [00000000-0000-0000-0000-000000000000]

julia> @import Bar
[ Info: Lazy-loading Bar [00000000-0000-0000-0000-000000000001]
ERROR: MissingPackage: Bar [00000000-0000-0000-0000-000000000001] has been required, but does not seem to be installed.
Stacktrace: [...]
```
"""
struct MissingPackage <: PackageException
    pkg::Base.PkgId
end

Base.showerror(io::IO, err::MissingPackage) =
    print(io, "MissingPackage: ", err.pkg.name, " [", err.pkg.uuid,
          "] has been required, but does not seem to be installed.")

abstract type DataOperationException <: Exception end

"""
    CollectionVersionMismatch(version::Int)

The version of the collection currently being acted on is not supported
by the current version of $(@__MODULE__).

# Example occurance

```julia-repl
julia> fromspec(DataCollection, SmallDict{String, Any}("data_config_version" => -1))
ERROR: CollectionVersionMismatch: -1 (specified) ≠ $LATEST_DATA_CONFIG_VERSION (current)
  The data collection specification uses the v-1 data collection format, however
  the installed DataToolkitBase version expects the v$LATEST_DATA_CONFIG_VERSION version of the format.
  In the future, conversion facilities may be implemented, for now though you
  will need to manually upgrade the file to the v$LATEST_DATA_CONFIG_VERSION format.
Stacktrace: [...]
```
"""
struct CollectionVersionMismatch <: DataOperationException
    version::Int
end

function Base.showerror(io::IO, err::CollectionVersionMismatch)
    print(io, "CollectionVersionMismatch: ", err.version, " (specified) ≠ ",
          LATEST_DATA_CONFIG_VERSION, " (current)\n")
    print(io, "  The data collection specification uses the v$(err.version) data collection format, however\n",
          "  the installed $(@__MODULE__) version expects the v$LATEST_DATA_CONFIG_VERSION version of the format.\n",
          "  In the future, conversion facilities may be implemented, for now though you\n  will need to ",
          ifelse(err.version < LATEST_DATA_CONFIG_VERSION,
                 "manually upgrade the file to the v$LATEST_DATA_CONFIG_VERSION format.",
                 "use a newer version of $(@__MODULE__)."))
end

"""
    EmptyStackError()

An attempt was made to perform an operation on a collection within the data
stack, but the data stack is empty.

# Example occurance

```julia-repl
julia> getlayer(nothing) # with an empty STACK
ERROR: EmptyStackError: The data collection stack is empty
Stacktrace: [...]
```
"""
struct EmptyStackError <: DataOperationException end

Base.showerror(io::IO, err::EmptyStackError) =
    print(io, "EmptyStackError: The data collection stack is empty")

"""
    ReadonlyCollection(collection::DataCollection)

Modification of `collection` is not viable, as it is read-only.

# Example Occurance

```julia-repl
julia> lockedcollection = DataCollection(SmallDict{String, Any}("uuid" => Base.UUID(rand(UInt128)), "config" => SmallDict{String, Any}("locked" => true)))
julia> write(lockedcollection)
ERROR: ReadonlyCollection: The data collection unnamed#298 is locked
Stacktrace: [...]
```
"""
struct ReadonlyCollection <: DataOperationException
    collection::DataCollection
end

Base.showerror(io::IO, err::ReadonlyCollection) =
    print(io, "ReadonlyCollection: The data collection ", err.collection.name,
          " is ", ifelse(get(err.collection, "locked", false) === true,
                         "locked", "backed by a read-only file"))

"""
    TransformerError(msg::String)

A catch-all for issues involving data transformers, with details given in `msg`.

# Example occurance

```julia-repl
julia> emptydata = DataSet(DataCollection(), "empty", SmallDict{String, Any}("uuid" => Base.UUID(rand(UInt128))))
DataSet empty

julia> read(emptydata)
ERROR: TransformerError: Data set "empty" could not be loaded in any form.
Stacktrace: [...]
```
"""
struct TransformerError <: DataOperationException
    msg::String
end

Base.showerror(io::IO, err::TransformerError) =
    print(io, "TransformerError: ", err.msg)

"""
    UnsatisfyableTransformer{T}(dataset::DataSet, types::Vector{QualifiedType})

A transformer (of type `T`) that could provide any of `types` was asked for, but
there is no transformer that satisfies this restriction.

# Example occurance

```julia-repl
julia> emptydata = DataSet(DataCollection(), "empty", SmallDict{String, Any}("uuid" => Base.UUID(rand(UInt128))))
DataSet empty

julia> read(emptydata, String)
ERROR: UnsatisfyableTransformer: There are no loaders for "empty" that can provide a String. The defined loaders are as follows:
Stacktrace: [...]
```
"""
struct UnsatisfyableTransformer{T} <: DataOperationException where { T <: AbstractDataTransformer }
    dataset::DataSet
    types::Vector{QualifiedType}
end

function Base.showerror(io::IO, err::UnsatisfyableTransformer{DataLoader})
    print(io, "UnsatisfyableTransformer: There are no loaders for ",
          sprint(show, err.dataset.name), " that can provide a ",
          join(string.(err.types), ", ", ", or "),
          ". The defined loaders are as follows:")
end

"""
    OrphanDataSet(dataset::DataSet)

The data set (`dataset`) is no longer a child of its parent collection.

This error should not occur, and is intended as a sanity check should
something go quite wrong.
"""
struct OrphanDataSet <: DataOperationException
    dataset::DataSet
end

function Base.showerror(io::IO, err::OrphanDataSet)
    print(io, "OrphanDataSet: The data set ", err.dataset.name,
          " [", err.dataset.uuid, "] is no longer a child of of its parent collection.\n",
          "This should not occur, and indicates that something fundamental has gone wrong.")
end

"""
    ImpossibleTypeException(qt::QualifiedType, mod::Union{Module, Nothing})

The qualified type `qt` could not be converted to a `Type`, for some reason or
another (`mod` is the parent module used in the attempt, should it be sucesfully
identified, and `nothing` otherwise).
"""
struct ImpossibleTypeException <: Exception
    qt::QualifiedType
    mod::Union{Module, Nothing}
end

function Base.showerror(io::IO, err::ImpossibleTypeException)
    print(io, "ImpossibleTypeException: Could not realise the type ", string(err.qt))
    if isnothing(err.mod)
        print(io, ", as the parent module ", err.qt.parentmodule,
              " is not loaded.")
    elseif !isdefined(err.mod, err.qt.name)
        print(io, ", as the parent module ", err.qt.parentmodule,
              " has no property ", err.qt.name, '.')
    else
        print(io, ", for unknown reasons, possibly an issue with the type parameters?")
    end
end
