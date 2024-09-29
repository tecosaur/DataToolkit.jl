"""
    QualifiedType

A representation of a Julia type that does not need the type to be defined in
the Julia session, and can be stored as a string. This is done by storing the
type name and the module it belongs to as Symbols.

!!! warning
    While `QualifiedType` is currently quite capable, it is not currently
    able to express the full gamut of Julia types. In future this will be improved,
    but it will likely always be restricted to a certain subset.

See also: [`typeify`](@ref).

# Subtyping

While the subtype operator cannot work on QualifiedTypes (`<:` is a built-in),
when the Julia types are defined the subset operator `⊆` can be used instead.
This works by simply `convert`ing the QualifiedTypes to the corresponding Type
and then applying the subtype operator.

```julia-repl
julia> QualifiedTypes(:Base, :Vector) ⊆ QualifiedTypes(:Core, :Array)
true

julia> Matrix ⊆ QualifiedTypes(:Core, :Array)
true

julia> QualifiedTypes(:Base, :Vector) ⊆ AbstractVector
true

julia> QualifiedTypes(:Base, :Foobar) ⊆ AbstractVector
false
```

# Constructors

```julia
QualifiedType(parentmodule::Symbol, typename::Symbol)
QualifiedType(t::Type)
```

# Parsing

A QualifiedType can be expressed as a string as `"\$parentmodule.\$typename"`.
This can be easily `parse`d as a QualifiedType, e.g. `parse(QualifiedType,
"Core.IO")`.
"""
struct QualifiedType
    root::Symbol
    parents::Vector{Symbol}
    name::Symbol
    parameters::Tuple
end

"""
    Identifier

A description that can be used to uniquely identify a DataSet.

Four fields are used to describe the target DataSet:
- `collection`, the name or UUID of the collection (optional).
- `dataset`, the name or UUID of the dataset.
- `type`, the type that should be loaded from the dataset.
- `parameters`, any extra parameters of the dataset that should match.

See also: [`resolve`](@ref), [`refine`](@ref).

# Constructors

```julia
Identifier(collection::Union{AbstractString, UUID, Nothing},
           dataset::Union{AbstractString, UUID},
           type::Union{QualifiedType, Nothing},
           parameters::Dict{String, Any})
```

# Parsing

An Identifier can be represented as a string with the following form,
with the optional components enclosed by square brackets:
```
[COLLECTION:]DATASET[::TYPE]
```

Such forms can be parsed to an Identifier by simply calling the `parse`
function, i.e. `parse(Identifier, "mycollection:dataset")`.
"""
struct Identifier
    collection::Union{AbstractString, UUID, Nothing}
    dataset::Union{AbstractString, UUID}
    type::Union{QualifiedType, Nothing}
    parameters::Dict{String, Any}
end

"""
    DataTransformer{kind, driver}

The parent type for structures producing or consuming data.

```text
                 ╭────loader─────╮
                 ╵               ▼
Storage ◀────▶ Data          Information
                 ▲               ╷
                 ╰────writer─────╯
```

There are three kinds of specialised `DataTransformer`s:
- [`DataStorage`](@ref)
- [`DataLoader`](@ref)
- [`DataWriter`](@ref)

Each transformer takes a `Symbol` type parameter designating
the driver which should be used to perform the data operation.

In addition, each transformer has the following fields:
- `dataset::DataSet`, the data set the method operates on
- `type::Vector{QualifiedType}`, the Julia types the method supports
- `priority::Int`, the priority with which this method should be used,
  compared to alternatives. Lower values have higher priority.
- `parameters::Dict{String, Any}`, any parameters applied to the method.

See also: [`DataStorage`](@ref), [`DataLoader`](@ref), [`DataWriter`](@ref), [`supportedtypes`](@ref).
"""
struct DataTransformer{kind, driver}
    dataset
    type::Vector{QualifiedType}
    priority::Int
    parameters::Dict{String, Any}
end

"""
    DataStorage <: DataTransformer

A [`DataTransformer`](@ref) that can retrieve data from a source,
and/or store data in a source.

```text
  Storage ◀────▶ Data
```

Typically a `DataStorage` will have methods implemented to provide
storage as a [`FilePath`](@ref) or `IO`, and potentially writable
`IO` or a [`FilePath`](@ref) that can be written to.

Data of a certain form retrieved from a storage backend of a [`DataSet`](@ref)
can be accessed by calling [`open`](@ref open(::DataSet, ::Type)) on the
dataset.

See also: [`storage`](@ref), [`getstorage`](@ref), [`putstorage`](@ref).

# Implementing a DataStorage backend

There are two ways a new `DataStorage` backend can be implemented:
- Implementing a single [`storage(ds::DataStorage{:name}, as::Type; write::Bool)`](@ref storage) method,
  that will provide an `as` handle for `ds`, in either read or write mode.
- Implement one or both of the following methods:
  - [`getstorage(ds::DataStorage{:name}, as::Type)`](@ref getstorage)
  - [`putstorage(ds::DataStorage{:name}, as::Type)`](@ref putstorage)

This split approach allows for backends with very similar read/write cases to be
easily implemented with a single [`storage`](@ref) method, while also allowing
for more backends with very different read/write methods or that only support
reading or writing exclusively to only implement the relevant method.

Optionally, the following extra methods can be implemented:
- [`supportedtypes`](@ref) when storage can be read/written to multiple forms,
  to give preference to certain types and help DataToolkit make reasonable assumptions
  (does nothing when only a single concrete type is supported)
- [`createauto`](@ref) and/or [`createinteractive`](@ref) to improve the user
  experience when creating instances of the storage backend.
- [`createpriority`](@ref), when you want to have automatic creation using
  this storage backend to be tried earlier or later than default by DataToolkit.

# Example storage backend implementation

For simple cases, it can only take a few lines to implement a storage backend.

This is the actual implementation of the [`:filesystem`](@extref storage-filesystem)
backend from `DataToolkitCommon`,

```julia
function storage(storage::DataStorage{:filesystem}, ::Type{FilePath}; write::Bool)
    path = getpath(storage)
    if @advise storage isfile(path)
        FilePath(path)
    end
end

function storage(storage::DataStorage{:filesystem}, ::Type{DirPath}; write::Bool)
    path = getpath(storage)
    if @advise storage isdir(path)
        DirPath(path)
    end
end
```

This provides support for both files and directories, assisted by
the helper function `getpath`, which retrieves the `"path"` parameter
using [`@getparam`](@ref) and then normalises it.

The `isfile`/`isdir` calls are wrapped in [`@advise`](@ref) to allow
plugins to dynamically perform additional or even potentially instantiate
a file on-demand.
"""
const DataStorage = DataTransformer{:storage}

"""
    DataLoader <: DataTransformer

A [`DataTransformer`](@ref) that interprets data into a useful form.

```text
    ╭────loader─────╮
    ╵               ▼
  Data          Information
```

Typically a `DataLoader` will have methods implemented to interpret
a raw data stream such as `IO` or a [`FilePath`](@ref) to a richer, more
informative form (such as a `DataFrame`).

A particular form can be loaded from a [`DataSet`](@ref) by calling
[`read`](@ref read(::DataSet, ::Type)) on the dataset.

See also: [`load`](@ref), [`supportedtypes`](@ref).

# Implementing a DataLoader backend

To provide a new `DataLoader` backend, you need to implement a [`load`](@ref)
method that will provide the data in the requested form:

    load(::DataLoader{:name}, source, as::Type)

Often the `load` implementation will make use of a helpful package. To avoid
eagerly loading the package, you can make use of [`@require`](@ref) and the lazy
loading system. In `DataToolkitCommon` this is combined with the package extension system,
resulting in loader implementations that look something like this:

```julia
function load(loader::DataLoader{:name}, from::IO, as::Vector{String})
    @require SomePkg
    param = @getparam loader."param"::Int 0
    invokelatest(_load_somepkg, from, param)
end

function _load_somepkg end # Implemented in a package extension
```

Depending on the number of loaders and other details this may be overkill in
some situations.

In order to matchmake `DataLoader`s and `DataStorage`s, DataToolkit engages in
what is essentially custom dispatch using reflection and method table
interrogation. In order for this to work well, the `source` and `as` arguments
should avoid using parametric types beyond the most simple case:

    load(::DataLoader{:name}, source::T, as::Type{T}) where {T}

In cases where a given `DataLoader` can provide multiple types, or
`Any`/parametric types, you can hint which types are most preferred
by implementing [`supportedtypes`](@ref) for the loader.
"""
const DataLoader = DataTransformer{:loader}

"""
    DataWriter <: DataTransformer

A [`DataTransformer`](@ref) that writes a representation of some information to
a source.

```text
  Data          Information
    ▲               ╷
    ╰────writer─────╯
```

Typically a `DataWriter` will have methods implemented to write a
structured form of the information to a more basic data format such as `IO`
or a [`FilePath`](@ref).

A compatible value can be written to a [`DataSet`](@ref) by calling
[`write`](@ref write(::DataSet, ::Any)) on the dataset.

# Implementing a DataWriter backend

To provide a new `DataWriter` backend, you need to implement a [`save`](@ref)
method that can write a value to a certain form.

    save(::DataWriter{:name}, destination, info)

As with [`DataLoader`](@ref)s, `DataWriter`s can also make use of the lazy
loading system and package extensions to avoid eager loading of packages.

Often the `save` implementation will make use of a helpful package. To avoid
eagerly saveing the package, you can make use of [`@require`](@ref) and the lazy
saveing system. In `DataToolkitCommon` this is combined with the package extension system,
resulting in saveer implementations that look something like this:

```julia
function save(writer::DataWriter{:name}, dest::IO, info::Vector{String})
    @require SomePkg
    invokelatest(_save_somepkg, info)
end

function _save_somepkg end # Implemented in a package extension
```

Depending on the number of loaders and other details this may be overkill in
some situations.

In cases where a given `DataWriter` can provide multiple types, or
`Any`/parametric types, you can hint which types are most preferred
by implementing [`supportedtypes`](@ref) for the loader.
"""
const DataWriter = DataTransformer{:writer}

"""
    Advice{func, context} <: Function

Advices allow for composable, highly flexible modifications of data by
encapsulating a function call. They are inspired by [elisp's advice
system](https://www.gnu.org/software/emacs/manual/html_node/elisp/Advising-Functions.html),
namely the most versatile form — `:around` advice, and [Clojure's transducers](https://clojure.org/reference/transducers).

A `Advice` is essentially a function wrapper, with a `priority::Int`
attribute. The wrapped functions should be of the form:

    (action::Function, args...; kargs...) ->
        ([post::Function], action::Function, args::Tuple, [kargs::NamedTuple])

Short-hand return values with `post` or `kargs` omitted are also accepted, in
which case default values (the `identity` function and `(;)` respectively) will
be automatically substituted in.

```text
    input=(action args kwargs)
         ┃                 ┏╸post=identity
       ╭─╂────advisor 1────╂─╮
       ╰─╂─────────────────╂─╯
       ╭─╂────advisor 2────╂─╮
       ╰─╂─────────────────╂─╯
       ╭─╂────advisor 3────╂─╮
       ╰─╂─────────────────╂─╯
         ┃                 ┃
         ▼                 ▽
action(args; kargs) ━━━━▶ post╺━━▶ result
```

To specify which transforms a Advice should be applied to, ensure you
add the relevant type parameters to your transducing function. In cases where
the transducing function is not applicable, the Advice will simply act
as the identity function.

After all applicable `Advice`s have been applied, `action(args...;
kargs...) |> post` is called to produce the final result.

The final `post` function is created by rightwards-composition with every `post`
entry of the advice forms (i.e. at each stage `post = post ∘ extra` is run).

The overall behaviour can be thought of as *shells* of advice.

```text
        ╭╌ advisor 1 ╌╌╌╌╌╌╌╌─╮
        ┆ ╭╌ advisor 2 ╌╌╌╌╌╮ ┆
        ┆ ┆                 ┆ ┆
input ━━┿━┿━━━▶ function ━━━┿━┿━━▶ result
        ┆ ╰╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╯ ┆
        ╰╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╯
```

# Constructors

```julia
Advice(priority::Int, f::Function)
Advice(f::Function) # priority is set to 1
```

# Examples

**1. Logging every time a DataSet is loaded.**

```julia
loggingadvisor = Advice(
    function(post::Function, f::typeof(load), loader::DataLoader, input, outtype)
        @info "Loading \$(loader.data.name)"
        (post, f, (loader, input, outtype))
    end)
```

**2. Automatically committing each data file write.**

```julia
writecommitadvisor = Advice(
    function(post::Function, f::typeof(write), writer::DataWriter{:filesystem}, output, info)
        function writecommit(result)
            run(`git add \$output`)
            run(`git commit -m "update \$output"`)
            result
        end
        (post ∘ writecommit, writefn, (output, info))
    end)
```
"""
struct Advice <: Function
    priority::Int # REVIEW should this be an Int?
    f::Function
end

"""
    Plugin

A named collection of [`Advice`](@ref) that accompanies [`DataCollection`](@ref)s.

The complete collection of advice provided by all plugins of a
[`DataCollection`](@ref) is applied to every [`@advise`](@ref)d call involving
the [`DataCollection`](@ref).

See also: [`Advice`](@ref), [`AdviceAmalgamation`](@ref).

# Construction

```julia
Plugin(name::String, advisors::Vector{Advice}) -> Plugin
Plugin(name::String, advisors::Vector{<:Function}) -> Plugin
```
"""
struct Plugin
    name::String
    advisors::Vector{Advice}
end

Plugin(name::String, advisors::Vector{<:Function}) =
    Plugin(name, map(Advice, advisors))

Plugin(name::String, advisors::Vector{<:Advice}) =
    Plugin(name, Vector{Advice}(advisors))

"""
    DataSet

A named collection of data, along with the means to retrive the source and
interpret in into a useful form.

```text
╭╴DataSet(name, UUID) ─▶ DataCollection╶─╮
│ ├╴Loaders: DataLoader,  […]            │
│ │  ╰╌◁╌╮                               │
│ ├╴Storage: DataStorage, […]            │
│ │  ╰╌◁╌╮                               │
│ └╴Writers: DataWriter,  […]            │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┤
│ Parameters(…)                          │
╰────────────────────────────────────────╯
```

More concretely, a `DataSet`:
- Belongs to a [`DataCollection`](@ref)
- Is identified by its name and a UUID
- Holds any number of key-value parameters
- Contains any number of [`DataStorage`](@ref), [`DataLoader`](@ref), and
  [`DataWriter`](@ref) transformers

The name or UUID can of a `DataSet` can be used (optionally with a given
`DataCollection`) to create an serializable [`Identifier`](@ref) that is able to
be resolved back to the `DataSet` in question.

The storage of a `DataSet` can be accessed with [`open(::DataSet,
::Type)`](@ref), and loaded with [`read(::DataSet, ::Type)`](@ref).

A `DataSet` can be directly instantiated using the method
```julia
DataSet(collection::DataCollection, name::String, uuid::UUID,
        parameter::Dict{String, Any}, storage::Vector{DataStorage},
        loaders::Vector{DataLoader}, writers::Vector{DataWriter})
```
but it is generally going to be more convenient to use [`create`](@ref) or
[`create!`](@ref) depending on whether you want the created dataset to be
registered in the [`DataCollection`](@ref) passed.

A `DataSet` can be also constructed from a TOML specification using
[`fromspec`](@ref), and a TOML spec created with [`tospec`](@ref).

Transformers can be added to a `DataSet` with [`create!`](@ref) or the dedicated
methods [`storage!`](@ref), [`loader!`](@ref), and [`writer!`](@ref).

See also: [`DataCollection`](@ref), [`DataStorage`](@ref), [`DataLoader`](@ref),
[`DataWriter`](@ref).
"""
struct DataSet
    collection
    name::String
    uuid::UUID
    parameters::Dict{String, Any}
    storage::Vector{DataStorage}
    loaders::Vector{DataLoader}
    writers::Vector{DataWriter}
end

"""
    AdviceAmalgamation

An `AdviceAmalgamation` is a collection of [`Advice`](@ref)s sourced from
available [`Plugin`](@ref)s.

Like individual `Advice`s, an `AdviceAmalgamation` can be called
as a function. However, it also supports the following convenience syntax:

    (::AdviceAmalgamation)(f::Function, args...; kargs...) # -> result

# Constructors

```julia
AdviceAmalgamation(advisors::Vector{Advice}, plugins_wanted::Vector{String}, plugins_used::Vector{String})
AdviceAmalgamation(plugins::Vector{String})
AdviceAmalgamation(collection::DataCollection)
```
"""
mutable struct AdviceAmalgamation
    advisors::Vector{Advice}
    plugins_wanted::Vector{String}
    plugins_used::Vector{String}
end

"""
    DataCollection

A collection of [`DataSet`](@ref)s, with global configuration,
[`Plugin`](@ref)s, and a few other extras.

```text
╭╴DataCollection(name, UUID, path, module)╶─╮
│ ├╴DataSet(…)                              │
│ ├╴DataSet                                 │
│ │ ├╴Loaders: DataLoader,  […]             │
│ │ │  ╰╌◁╌╮                                │
│ │ ├╴Storage: DataStorage, […]             │
│ │ │  ╰╌◁╌╮                                │
│ │ └╴Writers: DataWriter,  […]             │
│ ⋮                                         │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┤
│ Plugins(…)                                │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┤
│ Parameters(…)                             │
╰───────────────────────────────────────────╯
```

# Working with `DataCollection`s

It is usual for non-transient `DataCollections` to be put onto the
"[`STACK`](@ref)" (this is done automatically by [`loadcollection!`](@ref)).
This is a collection of globally known `DataCollection`s.

Being on the [`STACK`](@ref) allows a dataset to be retrieved by its name or
UUID using [`getlayer`](@ref), and for a `DataSets` in one `DataCollection` to
refer to a `DataSet` in another.

When using the `data>` REPL mode, the top collection on the stack is used
as a default target for all operations.

# Creating a `DataCollection`

A [Data.toml](@extref) file can be loaded as a `DataCollection` (and put on the
[`STACK`](@ref)) with [`loadcollection!`](@ref).

To programatically create a `DataToolkit` you can either call the full
constructor, but that's rather involved, and so a more convenient constructor is
also defined:

```julia
DataCollection(name::Union{String, Nothing}, [parameters::Dict{String, Any}];
               path::Union{String, Nothing} = nothing,
               uuid::UUID = uuid4(),
               plugins::Vector{String} = String[],
               mod::Module = Base.Main,
               parameters...) -> DataCollection
```

Note that `parameters` can either be provided as the second positional argument,
or extra keyword arguments, but not both.

Once a `DataCollection` has been created, [`DataSet`](@ref)s can be added
to it with [`create!`](@ref).

## Examples

```julia-repl
julia> DataCollection("test")
DataCollection: test
  Data sets:

julia> c1 = DataCollection(nothing, Dict("customparam" => 77))
DataCollection:
  Data sets:

julia> c2 = DataCollection("test2", plugins = ["defaults", "store"], customparam=77)
DataCollection: test2
  Plugins: defaults ✔, store ✔
  Data sets:

julia> c1.parameters
Dict{String, Any} with 1 entry:
  "customparam" => 77

julia> c2.parameters
Dict{String, Any} with 1 entry:
  "customparam" => 77
```

# Saving a `DataCollection`

After modifying a file-backed `DataCollection`, the file can be updated by
calling `write(::DataCollection)` (so long as
[`iswritable(::DataCollection)`](@ref) is `true`).

Any `DataCollection` can also be written to a particular destination with
`write(dest, ::DataCollection)`.

Writing a `DataCollection` to plaintext is *essentially* performed by calling
`TOML.print` on the result of `convert(::Type{Dict}, ::DataCollection)`.

# Fields

```julia
version::Int
name::Union{String, Nothing}
uuid::UUID
plugins::Vector{String}
parameters::Dict{String, Any}
datasets::Vector{DataSet}
path::Union{String, Nothing}
advise::AdviceAmalgamation
mod::Module
```
"""
struct DataCollection
    version::Int
    name::Union{String, Nothing}
    uuid::UUID
    plugins::Vector{String}
    parameters::Dict{String, Any}
    datasets::Vector{DataSet}
    path::Union{String, Nothing}
    advise::AdviceAmalgamation
    mod::Module
end

"""
    SystemPath

A string, but one that explicitly refers to a path on the system.

See also: [`FilePath`](@ref), [`DirPath`](@ref).
"""
abstract type SystemPath end

"""
    FilePath <: SystemPath

Crude stand in for a file path type, which is strangely absent from Base.

This allows for load/write method dispatch, and the distinguishing of
file content (as a `String`) from file paths.

See also: [`DirPath`](@ref).

# Examples

```julia-repl
julia> string(FilePath("some/path"))
"some/path"
```
"""
struct FilePath <: SystemPath
    path::String
end
Base.string(fp::FilePath) = fp.path

"""
    DirPath <: SystemPath

Signifies that a given string is in fact a path to a directory.

This allows for load/write method dispatch, and the distinguishing of
file content (as a String) from file paths.

See also: [`FilePath`](@ref).

# Examples

```julia-repl
julia> string(DirPath("some/path"))
"some/path"
```
"""
struct DirPath <: SystemPath
    path::String
end
Base.string(dp::DirPath) = dp.path
