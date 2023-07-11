# Example:
#---
# [data.loader]
# driver = "julia"
# type = ["Int"]
# function = "(; inp) -> length(inp)"
# arguments = { inp = "📇DATASET<<somelist::Vector>>" }

function getactfn(transformer::AbstractDataTransformer)
    path = @getparam transformer."path"::Union{String, Nothing}
    fnstr = @getparam transformer."function"::Union{String, Nothing}
    loadfn = if !isnothing(path)
        Base.include(transformer.dataset.collection.mod,
                     abspath(dirof(transformer.dataset.collection),
                             expanduser(@getparam transformer."pathroot"::String ""),
                             expanduser(path)))
    elseif !isnothing(fnstr)
        Base.eval(transformer.dataset.collection.mod,
                  Meta.parse(strip(fnstr)))
    else
        error("Neither path nor function is provided.")
    end
end

function load(loader::DataLoader{:julia}, ::Nothing, R::Type)
    if isempty(@getparam loader."input"::String "")
        loadfn = getactfn(loader)
        arguments = SmallDict{Symbol,Any}([
            Symbol(arg) => val
            for (arg, val) in @getparam(loader."arguments"::SmallDict)])
        cd(dirof(loader.dataset.collection)) do
            DataToolkitBase.invokepkglatest(loadfn; arguments...)::R
        end
    end
end

function load(loader::DataLoader{:julia}, from::Any, R::Type)
    if !isempty(@getparam loader."input"::String "")
        desired_type = typeify(QualifiedType(@getparam loader."input"::String ""))
        if from isa desired_type
            loadfn = getactfn(loader)
            arguments = Dict{Symbol,Any}(
                Symbol(arg) => val
                for (arg, val) in @getparam(loader."arguments"::SmallDict{String, Any}))
            cd(dirof(loader.dataset.collection)) do
                DataToolkitBase.invokepkglatest(loadfn, from; arguments...)::R
            end
        end
    end
end

function save(writer::DataWriter{:julia}, dest, info)
    writefn = getactfn(writer)
    arguments = Dict{Symbol,Any}(
        Symbol(arg) => val
        for (arg, val) in @getparam(loader."arguments"::SmallDict{String, Any}))
    cd(dirof(writer.dataset.collection)) do
        DataToolkitBase.invokepkglatest(writefn, dest, info; arguments...)
    end
end

createpriority(::Type{DataLoader{:julia}}) = 10

function create(::Type{DataLoader{:julia}}, source::String)
    if !isnothing(match(r"\.jl$"i, source)) &&
        (!isempty(STACK) && isfile(abspath(dirof(first(STACK)), expanduser(source))) ||
        isfile(expanduser(source)))
        ["path" => source]
    end
end

function lint(loader::DataLoader{:julia}, ::Val{:non_list_julia_args})
    if haskey(loader.parameters, "arguments") &&
        loader.parameters["arguments"] isa Vector
        fixer = if length(loader.parameters["arguments"]) == 1
            function (li::LintItem{DataLoader{:julia}})
                li.source.parameters["arguments"] =
                    first(li.source.parameters["arguments"])
                true
            end
        end
        LintItem(loader, :error, :non_list_julia_args,
                 "Argument set is a list of argument sets",
                 fixer, !isnothing(fixer))
    end
end

const JULIA_DOC = md"""
Load and write data via custom Julia scripts

The `julia` driver enables the *parsing* and *serialisation* of arbitrary data
to arbitrary information formats and vice versa via custom Julia functions run
within the scope of the parent module.

# Input/output

The `julia` driver either accepts /no/ direct input, or accepts input from storage
backends of the type specified by the `input` keyword. Thus, the provided
functions must take one of the following forms:

```julia
function (input; kwargs...)
    # Direct input form.
end
```

```julia
function (kwargs...)
    # No direct input form.
end
```

In both cases, additional information can be provided via the `arguments` keyword,
which supplies additional keyword arguments to the Julia function invoked. It is
worth remembering the special treatment of DataSet strings which are dynamically
resolved (see the examples).

Writer functions take two arguments, the destination (a handle to the storage
backend, usually `IO`) and the information to be serialised.

```julia
function (destination, info)
    # Write `info` to `destination`, and return
    # not-nothing if the operation succeeds.
end
```

# Parameters

- `input`: (loading only) The data type required for direct input.
- `path`: A local file path, relative to `pathroot` if provided or the directory of
  the data TOML file.
- `pathroot`: The root path to expand `path` against, relative to the directory of
  the data TOML file.
- `function`: The function as a string, inline in the data TOML file.
- `arguments`: Arguments to be provided to the called function.

# Usage examples

```julia
[[addone.loader]]
driver ` "julia"
input ` "Number"
function ` "n -> n+1"
```

```julia
[[combined.loader]]
driver ` "julia"
path ` "scripts/mergedata.jl"

[combined.loader.arguments]
foo ` "📇DATASET<<foo::DataFrame>>"
bar ` "📇DATASET<<bar::DataFrame>>"
baz ` "📇DATASET<<baz::DataFrame>>"
```

```julia
[[repeated.loader]]
driver ` "julia"
input ` "Integer"
function ` "(n::Integer; data::DataFrame) -> repeat(data, n)"
arguments ` { data ` "📇DATASET<<iris::DataFrame>>" }
```
"""
