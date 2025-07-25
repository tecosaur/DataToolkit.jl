# [Julia](@id saveload-julia)

Load and write data via custom Julia scripts

The `julia` driver enables the *parsing* and *serialisation* of arbitrary data to arbitrary information formats and vice versa via custom Julia functions run within the scope of the parent module.

# Input/output

The `julia` driver either accepts /no/ direct input, or accepts input from storage backends of the type specified by the `input` keyword. Thus, the provided functions must take one of the following forms:

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

In both cases, additional information can be provided via the `arguments` keyword, which supplies additional keyword arguments to the Julia function invoked. It is worth remembering the special treatment of DataSet strings which are dynamically resolved (see the examples).

Writer functions take two arguments, the destination (a handle to the storage backend, usually `IO`) and the information to be serialised.

```julia
function (destination, info)
    # Write `info` to `destination`, and return
    # not-nothing if the operation succeeds.
end
```

# Parameters

  * `input`: (loading only) The data type required for direct input.
  * `path`: A local file path, relative to `pathroot` if provided or the directory of the data TOML file.
  * `pathroot`: The root path to expand `path` against, relative to the directory of the data TOML file.
  * `function`: The function as a string, inline in the data TOML file.
  * `arguments`: Arguments to be provided to the called function.

# Usage examples

```julia
[[addone.loader]]
driver = "julia"
input = "Number"
function = "n -> n+1"
```

```julia
[[combined.loader]]
driver = "julia"
path = "scripts/mergedata.jl"

[combined.loader.arguments]
foo = "📇DATASET<<foo::DataFrame>>"
bar = "📇DATASET<<bar::DataFrame>>"
baz = "📇DATASET<<baz::DataFrame>>"
```

```julia
[[repeated.loader]]
driver = "julia"
input = "Integer"
function = "(n::Integer; data::DataFrame) -> repeat(data, n)"
arguments = { data = "📇DATASET<<iris::DataFrame>>" }
```


