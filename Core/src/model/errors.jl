abstract type IdentifierException <: Exception end

"""
    UnresolveableIdentifier{T}(identifier::Union{String, UUID}, [collection::DataCollection]) <: IdentifierException

No `T` (optionally from `collection`) could be found that matches `identifier`.

# Example occurrences

```julia-repl
julia> d"iirs"
ERROR: UnresolveableIdentifier: "iirs" does not match any available data sets
  Did you perhaps mean to refer to one of these data sets?
    ■:iris (75% match)
Stacktrace: [...]

julia> d"iris::Int"
ERROR: UnresolveableIdentifier: "iris::Int" does not match any available data sets
  Without the type restriction, however, the following data sets match:
    dataset:iris, which is available as a DataFrame, Matrix, CSV.File
Stacktrace: [...]
```
"""
struct UnresolveableIdentifier{T, I} <: IdentifierException where {T, I <: Union{String, UUID}}
    target::Type{T} # Prevent "unused type variable" warning
    identifier::I
    collection::Union{DataCollection, Nothing}
end

UnresolveableIdentifier{T}(ident::I, collection::Union{DataCollection, Nothing}=nothing) where {T, I <: Union{String, UUID}} =
    UnresolveableIdentifier{T, I}(T, ident, collection)

function Base.showerror(io::IO, err::UnresolveableIdentifier{DataSet, String}, bt; backtrace=true)
    print(io, "UnresolveableIdentifier: ", sprint(show, err.identifier),
          " does not match any available data sets")
    if !isnothing(err.collection)
        print(io, " in ", sprint(show, err.collection.name))
    end
    # Check to see if there are any matches without the
    # type restriction (if applicable).
    notypematches = Vector{DataSet}()
    if err.identifier isa String
        if !isnothing(err.collection)
            ident = @advise err.collection parse_ident(err.identifier)::Identifier
            if !isnothing(ident.type)
                identnotype = Identifier(ident.collection, ident.dataset,
                                         nothing, ident.parameters)
                notypematches = refine(
                    err.collection, err.collection.datasets, identnotype)
            end
        else
            for collection in STACK
                ident = @advise collection parse_ident(err.identifier)::Identifier
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
            print(io, ", which is available as a ")
            types = getfield.(dataset.loaders, :type) |> Iterators.flatten |> unique
            for type in types
                printstyled(io, string(type), color=:yellow)
                type === last(types) || print(io, ", ")
            end
        end
    else
        candidates = Tuple{Identifier, DataCollection, Float64}[]
        if !isnothing(err.collection) || !isempty(STACK)
            let collection = @something(err.collection, first(STACK))
                for ident in Identifier.(collection.datasets, nothing)
                    istr = @advise collection string(ident)::String
                    push!(candidates,
                        (ident, collection, stringsimilarity(err.identifier, istr; halfcase=true)))
                end
            end
        elseif isnothing(err.collection) && !isempty(STACK)
            for collection in last(Iterators.peel(STACK))
                for ident in Identifier.(collection.datasets)
                    istr = @advise collection string(ident)::String
                    push!(candidates,
                        (ident, collection, stringsimilarity(err.identifier, istr; halfcase=true)))
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
                irep = IOContext(IOBuffer(), :color => true, :data_collection => collection)
                show(irep, MIME("text/plain"), ident)
                highlight_lcs(io, String(take!(irep.io)), err.identifier,
                              before="\e[2m", invert=true)
                printstyled(io, " (", round(Int, 100*sim), "% match)",
                            color=:light_black)
            end
        end
    end
    backtrace && println(io)
    backtrace && Base.show_backtrace(io, strip_stacktrace_advice!(bt))
end

function Base.showerror(io::IO, err::UnresolveableIdentifier{DataCollection}, bt; backtrace=true)
    print(io, "UnresolveableCollection: No collections within the stack matched the ",
          ifelse(err.identifier isa UUID, "identifier ", "name "), string(err.identifier))
    if err.identifier isa String
        candidates = Tuple{DataCollection, Float64}[]
        for collection in STACK
            if !isnothing(collection.name)
                push!(candidates,
                      (collection, stringsimilarity(err.identifier, collection.name; halfcase=true)))
            end
        end
        if maximum(last.(candidates), init=0.0) >= 0.5
            print(io, "\n  Did you perhaps mean to refer to one of these data collections?")
            for (collection, similarity) in candidates
                print(io, "\n  • ")
                crep = IOContext(IOBuffer(), :color => true, :compact => true)
                show(crep, MIME("text/plain"), collection)
                highlight_lcs(io, String(take!(crep.io)), err.identifier,
                              before="\e[2m", invert=true)
                printstyled(io, " (", round(Int, 100*similarity), "% similarity)",
                            color=:light_black)
            end
        end
    end
    backtrace && println(io)
    backtrace && Base.show_backtrace(io, strip_stacktrace_advice!(bt))
end

"""
    AmbiguousIdentifier(identifier::Union{String, UUID}, matches::Vector, [collection]) <: IdentifierException

Searching for `identifier` (optionally within `collection`), found multiple
matches (provided as `matches`).

# Example occurrence

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

function Base.showerror(io::IO, err::AmbiguousIdentifier{DataSet, I}, bt; backtrace=true) where {I}
    print(io, "AmbiguousIdentifier: ", sprint(show, err.identifier),
          " matches multiple data sets")
    if I == String
        for dataset in err.matches
            ident = Identifier(dataset, ifelse(err.collection === dataset.collection,
                                            nothing, :name))
            print(io, "\n    ")
            show(IOContext(io, :data_collection => dataset.collection),
                 MIME("text/plain"), ident)
            printstyled(io, " [", dataset.uuid, ']', color=:light_black)
        end
    else
        print(io, ". There is likely some kind of accidental ID duplication occurring.")
    end
    backtrace && println(io)
    backtrace && Base.show_backtrace(io, strip_stacktrace_advice!(bt))
end

function Base.showerror(io::IO, err::AmbiguousIdentifier{DataCollection}, bt; backtrace=true)
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
    backtrace && println(io)
    backtrace && Base.show_backtrace(io, strip_stacktrace_advice!(bt))
end

abstract type PackageException <: Exception end

"""
    UnregisteredPackage(pkg::Symbol, mod::Module) <: PackageException

The package `pkg` was asked for within `mod`, but has not been
registered by `mod`, and so cannot be loaded.

# Example occurrence

```julia-repl
julia> @require Foo
ERROR: UnregisteredPackage: Foo has not been registered by Main, see @addpkg for more information
Stacktrace: [...]
```
"""
struct UnregisteredPackage <: PackageException
    pkg::Symbol
    mod::Module
end

function Base.showerror(io::IO, err::UnregisteredPackage, bt; backtrace=true)
    print(io, "UnregisteredPackage: ", err.pkg,
          " has not been registered by ", err.mod)
    project_deps = let proj_file = if isnothing(pathof(err.mod)) # Main, etc.
        Base.active_project()
    else abspath(pathof(err.mod), "..", "..", "Project.toml") end
        if isfile(proj_file)
            Dict{String, Base.UUID}(
                pkg => Base.UUID(id)
                for (pkg, id) in get(Base.parsed_toml(proj_file),
                                     "deps", Dict{String, Any}()))
        else
            Dict{String, Base.UUID}()
        end
    end
    dtk = "DataToolkit" => Base.UUID("dc83c90b-d41d-4e55-bdb7-0fc919659999")
    has_dtk = dtk in project_deps
    print(io, ", see ",
          ifelse(has_dtk, "@addpkg", "addpkg"),
          " for more information")
    if haskey(project_deps, String(err.pkg))
        println(io, "\n The package is present as a dependency of $(err.mod), and so this issue can likely be fixed by invoking:")
        if has_dtk
            print(io, "   @addpkg $(err.pkg)")
        else
            print(io, "   addpkg($(err.mod), :$(err.pkg), $(sprint(show, project_deps[String(err.pkg)])))")
        end
    else
        print(io, " (it is also worth noting that the package does not seem to be present as a dependency of $(err.mod))")
    end
    backtrace && println(io)
    backtrace && Base.show_backtrace(io, strip_stacktrace_advice!(bt))
end

"""
    MissingPackage(pkg::Base.PkgId) <: PackageException

The package `pkg` was asked for, but does not seem to be available in the
current environment.

# Example occurrence

```julia-repl
julia> @addpkg Bar "00000000-0000-0000-0000-000000000000"
Bar [00000000-0000-0000-0000-000000000000]

julia> @require Bar
[ Info: Lazy-loading Bar [00000000-0000-0000-0000-000000000001]
ERROR: MissingPackage: Bar [00000000-0000-0000-0000-000000000001] has been required, but does not seem to be installed.
Stacktrace: [...]
```
"""
struct MissingPackage <: PackageException
    pkg::Base.PkgId
end

function Base.showerror(io::IO, err::MissingPackage, bt; backtrace=true)
    print(io, "MissingPackage: ", err.pkg.name, " [", err.pkg.uuid,
          "] has been required, but does not seem to be installed.")
    backtrace && Base.show_backtrace(io, strip_stacktrace_advice!(bt))
end

abstract type DataOperationException <: Exception end

"""
    CollectionVersionMismatch(version::Int) <: DataOperationException

The `version` of the collection currently being acted on is not supported
by the current version of $(@__MODULE__).

# Example occurrence

```julia-repl
julia> fromspec(DataCollection, Dict{String, Any}("data_config_version" => -1))
ERROR: CollectionVersionMismatch: -1 (specified) ≠ $LATEST_DATA_CONFIG_VERSION (current)
  The data collection specification uses the v-1 data collection format, however
  the installed DataToolkitCore version expects the v$LATEST_DATA_CONFIG_VERSION version of the format.
  In the future, conversion facilities may be implemented, for now though you
  will need to manually upgrade the file to the v$LATEST_DATA_CONFIG_VERSION format.
Stacktrace: [...]
```
"""
struct CollectionVersionMismatch <: DataOperationException
    version::Int
end

function Base.showerror(io::IO, err::CollectionVersionMismatch, bt; backtrace=true)
    print(io, "CollectionVersionMismatch: ", err.version, " (specified) ≠ ",
          LATEST_DATA_CONFIG_VERSION, " (current)\n")
    print(io, "  The data collection specification uses the v$(err.version) data collection format, however\n",
          "  the installed $(@__MODULE__) version expects the v$LATEST_DATA_CONFIG_VERSION version of the format.\n",
          "  In the future, conversion facilities may be implemented, for now though you\n  will need to ",
          ifelse(err.version < LATEST_DATA_CONFIG_VERSION,
                 "manually upgrade the file to the v$LATEST_DATA_CONFIG_VERSION format.",
                 "use a newer version of $(@__MODULE__)."))
    backtrace && println(io)
    backtrace && Base.show_backtrace(io, strip_stacktrace_advice!(bt))
end

"""
    EmptyStackError() <: DataOperationException

An attempt was made to perform an operation on a collection within the data
stack, but the data stack is empty.

# Example occurrence

```julia-repl
julia> getlayer() # with an empty STACK
ERROR: EmptyStackError: The data collection stack is empty
Stacktrace: [...]
```
"""
struct EmptyStackError <: DataOperationException end

function Base.showerror(io::IO, err::EmptyStackError, bt; backtrace=true)
    print(io, "EmptyStackError: The data collection stack is empty")
    backtrace && Base.show_backtrace(io, strip_stacktrace_advice!(bt))
end

"""
    ReadonlyCollection(collection::DataCollection) <: DataOperationException

Modification of `collection` is not viable, as it is read-only.

# Example Occurrence

```julia-repl
julia> lockedcollection = DataCollection(Dict{String, Any}("uuid" => Base.UUID(rand(UInt128)), "config" => Dict{String, Any}("locked" => true)))
julia> write(lockedcollection)
ERROR: ReadonlyCollection: The data collection unnamed#298 is locked
Stacktrace: [...]
```
"""
struct ReadonlyCollection <: DataOperationException
    collection::DataCollection
end

function Base.showerror(io::IO, err::ReadonlyCollection, bt; backtrace=true)
    print(io, "ReadonlyCollection: The data collection ", err.collection.name,
          " is ", ifelse(get(err.collection, "locked", false) === true,
                         "locked", "backed by a read-only file"))
    backtrace && Base.show_backtrace(io, strip_stacktrace_advice!(bt))
end

"""
    TransformerError(msg::String) <: DataOperationException

A catch-all for issues involving data transformers, with details given in `msg`.

# Example occurrence

```julia-repl
julia> emptydata = DataSet(DataCollection(), "empty", Dict{String, Any}("uuid" => Base.UUID(rand(UInt128))))
DataSet empty

julia> read(emptydata)
ERROR: TransformerError: Data set "empty" could not be loaded in any form.
Stacktrace: [...]
```
"""
struct TransformerError <: DataOperationException
    msg::String
end

function Base.showerror(io::IO, err::TransformerError, bt; backtrace=true)
    print(io, "TransformerError: ", err.msg)
    backtrace && Base.show_backtrace(io, strip_stacktrace_advice!(bt))
end

"""
    UnsatisfyableTransformer{T}(dataset::DataSet, types::Vector{QualifiedType}) <: DataOperationException

A transformer (of type `T`) that could provide any of `types` was asked for, but
there is no transformer that satisfies this restriction.

# Example occurrence

```julia-repl
julia> emptydata = DataSet(DataCollection(), "empty", Dict{String, Any}("uuid" => Base.UUID(rand(UInt128))))
DataSet empty

julia> read(emptydata, String)
ERROR: UnsatisfyableTransformer: There are no loaders for "empty" that can provide a String. The defined loaders are as follows:
Stacktrace: [...]
```
"""
struct UnsatisfyableTransformer{T} <: DataOperationException where { T <: DataTransformer }
    dataset::DataSet
    transformer::Type{T}
    wanted::Vector{QualifiedType}
end

function Base.showerror(io::IO, err::UnsatisfyableTransformer, bt; backtrace=true)
    transformer_type = lowercase(replace(string(nameof(err.transformer)), "Data" => ""))
    print(io, "UnsatisfyableTransformer: There are no $(transformer_type)s for ",
          sprint(show, err.dataset.name), " that can provide a ",
          join(string.(err.wanted), ", ", ", or "),
          ".\n The defined $(transformer_type)s are as follows:")
    transformers = if err.transformer <: DataLoader
        err.dataset.loaders
    else
        err.dataset.storage
    end
    for transformer in transformers
        print(io, "\n   ")
        show(io, transformer)
        tsteps = if transformer isa DataStorage
            typesteps(transformer, Any, write=false)
        else
            typesteps(transformer, Any)
        end
        print(io, " -> [", join(map(last, tsteps), ", "), ']')
    end
    backtrace && println(io)
    backtrace && Base.show_backtrace(io, strip_stacktrace_advice!(bt))
end

"""
    OrphanDataSet(dataset::DataSet) <: DataOperationException

The data set (`dataset`) is no longer a child of its parent collection.

This error should not occur, and is intended as a sanity check should
something go quite wrong.
"""
struct OrphanDataSet <: DataOperationException
    dataset::DataSet
end

function Base.showerror(io::IO, err::OrphanDataSet, bt; backtrace=true)
    print(io, "OrphanDataSet: The data set ", err.dataset.name,
          " [", err.dataset.uuid, "] is no longer a child of of its parent collection.\n",
          "This should not occur, and indicates that something fundamental has gone wrong.")
    backtrace && println(io)
    backtrace && Base.show_backtrace(io, strip_stacktrace_advice!(bt))
end

"""
    ImpossibleTypeException(qt::QualifiedType, mod::Union{Module, Nothing}) <: DataOperationException

The qualified type `qt` could not be converted to a `Type`, for some reason or
another (`mod` is the parent module used in the attempt, should it be successfully
identified, and `nothing` otherwise).
"""
struct ImpossibleTypeException <: Exception
    qt::QualifiedType
    mod::Union{Module, Nothing}
end

function Base.showerror(io::IO, err::ImpossibleTypeException, bt; backtrace=true)
    print(io, "ImpossibleTypeException: Could not realise the type ", string(err.qt))
    if isnothing(err.mod)
        print(io, ", as the parent module ", err.qt.root,
              " is not loaded.")
    elseif !isdefined(err.mod, err.qt.name)
        print(io, ", as the parent module ", err.qt.root,
              " has no property ", err.qt.name, '.')
    else
        print(io, ", for unknown reasons, possibly an issue with the type parameters?")
    end
    backtrace && Base.show_backtrace(io, strip_stacktrace_advice!(bt))
end

"""
    InvalidParameterType{T}(thing::T, parameter::String, type::Type) <: DataOperationException

The parameter `parameter` of `thing` must be of type `type`, but is not.
"""
struct InvalidParameterType{T <: Union{<:DataTransformer, DataSet, DataCollection}}
    thing::T
    parameter::String
    type::Type
end

function Base.showerror(io::IO, err::InvalidParameterType{DataTransformer{kind, driver}}, bt; backtrace=true) where {kind, driver}
    @nospecialize err
    print(io, "InvalidParameterType: '", err.parameter, "' parameter of ",
          err.thing.dataset.name, "'s ", sprint(show, DataTransformer{kind}),
          "{:", string(driver), "} must be a ",
          string(err.type), " not a ",
          string(typeof(get(err.thing, err.parameter))), ".")
    backtrace && Base.show_backtrace(io, strip_stacktrace_advice!(bt))
end

function Base.showerror(io::IO, err::InvalidParameterType, bt; backtrace=true)
    print(io, "InvalidParameterType: '", err.parameter, "' parameter of ",
          string(err.thing), " must be a ", string(err.type), " not a ",
          string(typeof(get(err.thing, err.parameter))), ".")
    backtrace && Base.show_backtrace(io, strip_stacktrace_advice!(bt))
end

"""
    @getparam container."parameter"::Type default=nothing

Get the parameter `"parameter"` from `container` (a [`DataCollection`](@ref),
[`DataSet`](@ref), or [`DataTransformer`](@ref)), ensuring that it is of type
`Type`. If it is not, an [`InvalidParameterType`](@ref) error is thrown.
"""
macro getparam(expr::Expr, default=nothing)
    thing, type = if Meta.isexpr(expr, :(::)) expr.args else (expr, :Any) end
    Meta.isexpr(thing, :.) || error("Malformed expression passed to @getparam")
    root, param = thing.args
    if isnothing(default)
        typename = if type isa Symbol type
        elseif Meta.isexpr(type, :curly) first(type.args)
        else :Any end
        default = if typename ∈ (:Vector, :Dict)
            :($type())
        else :nothing end
    end
    if type == :Any
        :(get($(esc(root)), $(esc(param)), $(esc(default))))
    else
        quote
            let value = get($(esc(root)), $(esc(param)), $(esc(default)))
                if !(value isa $(esc(type)))
                    throw(InvalidParameterType(
                        $(esc(root)), $(esc(param)), $(esc(type))))
                end
                value
            end
        end
    end
end
