struct QualifiedType
    parentmodule::Symbol
    name::Symbol
end

struct Identifier
    collection::Union{AbstractString, UUID, Nothing}
    dataset::Union{AbstractString, UUID}
    type::Union{QualifiedType, Nothing}
    parameters::Dict{String, Any}
end

"""
The supertype for methods producing or consuming data.
```
                 ╭────loader─────╮
                 ╵               ▼
Storage ◀────▶ Data          Information
                 ▲               ╷
                 ╰────writer─────╯
```

There are three subtypes:
- `DataStorage`
- `DataLoader`
- `DataWrite`

Each subtype takes a `Symbol` type parameter designating
the driver which should be used to perform the data operation.
In addition, each subtype has the following fields:
- `dataset::DataSet`, the data set the method operates on
- `supports::Vector{QualifiedType}`, the Julia types the method supports
- `priority::Int`, the priority with which this method should be used,
  compared to alternatives. Lower values have higher priority.
- `parameters::Dict{String, Any}`, any parameters applied to the method.
"""
abstract type AbstractDataTransformer end

struct DataStorage{driver, T} <: AbstractDataTransformer
    dataset::T
    supports::Vector{QualifiedType}
    priority::Int
    parameters::Dict{String, Any}
end

struct DataLoader{driver} <: AbstractDataTransformer
    dataset
    supports::Vector{QualifiedType}
    priority::Int
    parameters::Dict{String, Any}
end

struct DataWriter{driver} <: AbstractDataTransformer
    dataset
    supports::Vector{QualifiedType}
    priority::Int
    parameters::Dict{String, Any}
end

"""
    DataTransducer{context, func} <: Function
DataTransducers allow for composible, highly flexible modifications of data by
encapsulating a function call. They are inspired by elisp's advice system,
namely the most versitile form — `:around` advice, and Clojure's transducers.

```
        ╭ transducer #1 ╌╌╌─╮
        ┆ ╭ transducer #2 ╌╌┼╌╮
        ┆ ┆                 ┆ ┆
input ━━┿━┿━━━▶ function ━━━┿━┿━━▶ result
        ┆ ╰╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╯
        ╰╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╯
```

A `DataTransducer` is esentially a function wrapper, with a `priority::Int`
attribute. The wrapped functions should be functions of the form:
```julia
(post::Function, action::Function, args...; kargs...) ->
  (post::Function, action::Function, args, kargs)
```

A three-tuple result with `kargs` ommited is also accepted, in which case the an
empty kargs value will be automatically substituted as the fourth value.

To specify which transforms a DataTransducer should be applied to, ensure you
add the relevant type parameters to your transducing function. In cases where
the transducing function is not applicable, the DataTransducer will simply act
as the identity function.

After all applicable `DataTransducer`s have been applied, `action(args...;
kargs...) |> post` is called to produce the final result.

# Constructors

```julia
DataTransducer(priority::Int, f::Function)
DataTransducer(f::Function) # priority is set to 1
```

# Examples

Should you want to log every time a DataSet is loaded, one could
write the following DataTransducer:
```julia
loggingtransducer = DataTransducer(
    function(post::Function, f::typeof(load), loader::DataLoader, input, outtype)
        @info "Loading \$(loader.data.name)"
        (post, f, (loader, input, outtype))
    end)
```

Should you wish to automatically commit each write:
```julia
writecommittransducer = DataTransducer(
    function(post::Function, f::typeof(write), writer::DataWriter{:filesystem}, output, info)
        function writecommit(result)
            run(`git commit \$output`)
            result
        end
        (writecommit ∘ post, writefn, (output, info))
    end)
```
"""
struct DataTransducer{func, context} <: Function
    priority::Int # REVIEW should this be an Int?
    f::Function
    function DataTransducer(priority::Int, f::Function)
        validmethods = methods(f, Tuple{Function, Function, Any, Vararg{Any}})
        if length(validmethods) === 0
            throw(ArgumentError("Transducing function $f had no valid methods."))
        end
        functype, context = first(validmethods).sig.types[[3, 4]]
        new{functype, context}(priority, f)
    end
end

struct Plugin
    # TODO no module support (yet)! Maybe a handy macro could be good for this?
    name::String
    transducers::Vector{DataTransducer}
    Plugin(name::String, transducers::Vector{<:Function}) =
        new(name, DataTransducer.(transducers))
end

struct DataStore
    name::AbstractString
    storage::DataStorage
end

struct DataSet
    collection
    name::String
    uuid::UUID
    store::String
    parameters::Dict{String, Any}
    storage::Vector{DataStorage}
    loaders::Vector{DataLoader}
    writers::Vector{DataWriter}
end

mutable struct DataTransducerAmalgamation
    transduceall::Function
    transducers::Vector{DataTransducer}
    plugins_wanted::Vector{String}
    plugins_used::Vector{String}
end

struct DataCollection
    version::Int
    name::Union{String, Nothing}
    uuid::UUID
    plugins::Vector{String}
    stores::Vector{DataStore} # could this be a plugin?
    parameters::Dict{String, Any}
    datasets::Vector{DataSet}
    path::Union{String, Nothing}
    transduce::DataTransducerAmalgamation
end
