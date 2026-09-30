"""
    versions_ident_parse_a( <parse_ident(ident::AbstractString)> )

Advice that parses the version from the identifier.

Part of `VERSIONS_PLUGIN`.
"""
function versions_ident_parse_a(f::typeof(parse_ident), ident::AbstractString)
    function extractversion!(ident::Identifier)
        if ident.dataset isa AbstractString && count('@', ident.dataset) == 1
            name, version = split(ident.dataset, '@')
            ident.parameters["version"] = version
            Identifier(ident.collection, String(name), ident.type, ident.parameters)
        else
            ident
        end
    end
    (extractversion!, f, (ident,))
end

"""
    VersionSelector

A parsed version selector: a union of half-open `[lower, upper)` intervals over
a version's `major.minor.patch`. As in Pkg, a candidate's prerelease and build
suffixes are ignored when matching.

Construct one with `tryparse(VersionSelector, selector)`.
"""
struct VersionSelector
    intervals::Vector{NTuple{2, VersionNumber}}
end

function Base.in(v::VersionNumber, sel::VersionSelector)
    release = VersionNumber(v.major, v.minor, v.patch)
    any(((lower, upper),) -> lower <= release < upper, sel.intervals)
end

"""
    tryparse(VersionSelector, selector::AbstractString) -> Union{VersionSelector, Nothing}

Parse `selector`, which is one of:
- `latest`, matching every version;
- a bare version (`1`, `1.2`, `1.2.3`), matching the versions that agree with
  it on every component given, so `1.2` matches `1.2.x`;
- a comma-separated union of [Pkg-style version specifiers
  ](https://pkgdocs.julialang.org/v1/compatibility/#Version-specifier-format):
  `^1.2` (the default, so `1.2, 1.4` is `^1.2, ^1.4`), `~1.2`, `=1.2.3`,
  `>=1.2`, `≥1.2`, `<2`, and `1.2 - 1.4`.

Return `nothing` when `selector` is none of these.
"""
function Base.tryparse(::Type{VersionSelector}, selector::AbstractString)
    selector == "latest" && return VersionSelector([(v"0", typemax(VersionNumber))])
    if !isempty(selector) && all(c -> c ∈ '0':'9' || c == '.', selector)
        (version, n) = @something(versionbound(selector), return)
        return VersionSelector([(version, successor(version, n))])
    end
    intervals = NTuple{2, VersionNumber}[]
    for clause in eachsplit(selector, ',')
        push!(intervals, @something(versioninterval(strip(clause)), return))
    end
    VersionSelector(intervals)
end

const VERSION_OPERATORS = (">=", "≥", "<", "=", "~", "^")

function versionbound(bound::AbstractString)
    parts = split(chopprefix(bound, "v"), '.')
    length(parts) <= 3 && all(p -> !isempty(p) && all(isdigit, p), parts) || return
    numbers = map(p -> tryparse(UInt32, p), parts)
    any(isnothing, numbers) && return
    (VersionNumber(ntuple(i -> get(numbers, i, 0x0), 3)...), length(parts))
end

# The least release above every version agreeing with `v` on its first `n` components.
function successor(v::VersionNumber, n::Int)
    parts = (v.major, v.minor, v.patch)
    i = findlast(j -> parts[j] < typemax(UInt32), 1:n) # Carry past saturated components.
    isnothing(i) && return typemax(VersionNumber)
    VersionNumber(ntuple(j -> if j < i parts[j] elseif j == i parts[j] + 0x1 else 0x0 end, 3)...)
end

function versioninterval(clause::AbstractString)
    words = split(clause)
    if length(words) == 3 && words[2] == "-"
        (lower, _) = @something(versionbound(words[1]), return)
        (upper, n) = @something(versionbound(words[3]), return)
        return (lower, successor(upper, n))
    end
    i = findfirst(o -> startswith(clause, o), VERSION_OPERATORS)
    op = if isnothing(i) "^" else VERSION_OPERATORS[i] end
    rest = chopprefix(clause, op)
    # Only a comparison may be spaced from its version.
    bound = if op in ("~", "^") rest else lstrip(rest) end
    (v, n) = @something(versionbound(bound), return)
    if op == ">=" || op == "≥"; (v, typemax(VersionNumber))
    elseif op == "<"; (v"0", v)
    elseif op == "="; (v, successor(v, 3))
    elseif op == "~"; (v, successor(v, min(n, 2)))
    else # Caret: fix everything up to the first nonzero component.
        (v, successor(v, something(findfirst(!iszero, (v.major, v.minor, v.patch)), n)))
    end
end

"""
    InvalidVersionSelector(identifier::Identifier, selector::String) <: IdentifierException

The version `selector` of `identifier` is not one the `versions` plugin understands.

# Example occurrence

```julia-repl
julia> dataset("iris@>1")
ERROR: InvalidVersionSelector: ">1" (of "iris") is not a version selector.
  Use `latest`, a version such as `1.2`, or Pkg-style specifiers (`~1.2`, `^1`, `=1.2.3`, `>=1.2`, `<2`, `1.2 - 1.4`) joined by commas.
```
"""
struct InvalidVersionSelector <: DataToolkitCore.IdentifierException
    identifier::Identifier
    selector::String
end

function Base.showerror(io::IO, err::InvalidVersionSelector, bt; backtrace=true)
    print(io, "InvalidVersionSelector: ", sprint(show, err.selector), " (of ",
          sprint(show, string(err.identifier)), ") is not a version selector.\n",
          "  Use `latest`, a version such as `1.2`, or Pkg-style specifiers ",
          "(`~1.2`, `^1`, `=1.2.3`, `>=1.2`, `<2`, `1.2 - 1.4`) joined by commas.")
    backtrace && Base.show_backtrace(io, DataToolkitCore.strip_stacktrace_advice!(bt))
end

"""
    versions_refine_a( <refine(datasets::Vector{DataSet}, ident::Identifier, ignoreparams::Vector{String})> )

Advice that refines the data sets to the highest version matching the
identifier's `"version"` selector.

Part of `VERSIONS_PLUGIN`.
"""
function versions_refine_a(f::typeof(refine), datasets::Vector{DataSet}, ident::Identifier, ignoreparams::Vector{String})
    if haskey(ident.parameters, "version")
        rawselector = String(ident.parameters["version"])
        selector = @something(tryparse(VersionSelector, rawselector),
                              throw(InvalidVersionSelector(ident, rawselector)))
        versions = [something(if haskey(ds.parameters, "version")
                                  tryparse(VersionNumber, string(ds.parameters["version"]))
                              end, v"0") for ds in datasets]
        matching = filter(∈(selector), versions)
        datasets = if isempty(matching) DataSet[] else datasets[versions .== maximum(matching)] end
        push!(ignoreparams, "version")
    end
    (f, (datasets, ident, ignoreparams))
end

"""
    versions_ident_string_a( <string(ident::Identifier)> )

Advice that appends the version to the identifier when stringifying it.

Part of `VERSIONS_PLUGIN`.
"""
function versions_ident_string_a(f::typeof(string), ident::Identifier)
    if haskey(ident.parameters, "version")
        ident = Identifier(
            ident.collection,
            string(ident.dataset, '@',
                    ident.parameters["version"]),
            ident.type,
            delete!(copy(ident.parameters), "version"))
    end
    (f, (ident,))
end

"""
    versions_do_lint_a( <lint(f::typeof(lint), obj::DataSet, linters::Vector{Method})> )

Advice that adds all versions linters to the linters list.

Part of `VERSIONS_PLUGIN`.
"""
function versions_do_lint_a(f::typeof(lint), obj::DataSet, linters::Vector{Method})
    append!(linters, methods(lint_versions, Tuple{DataSet, Val}).ms)
    (f, (obj, linters))
end

"""
Give data sets versions, and identify them by version.

### Giving data sets a version

Multiple editions of a data set can be described by using the same name,
but setting the `version` parameter to differentiate them.

For instance, say that Ronald Fisher released a second version of the "Iris"
data set, with more flowers. We could specify this as:

```toml
[[iris]]
version = "1"
...

[[iris]]
version = "2"
...
```

### Matching by version

Version matching is done via the `Identifier` parameter `"version"`.
As shorthand, instead of providing the `"version"` parameter manually,
the version can be tacked onto the end of an identifier with `@`, e.g. `iris@1`
or `iris@2`.

The version matching follows
[`Pkg`'s version specifier format](https://pkgdocs.julialang.org/v1/compatibility/#Version-specifier-format),
with three notable differences:
- In addition to numeric versioning, you can just ask for the "latest" version
- Numeric versions with no explicit scheme are matched up to the level of granularity
  explicitly provided. For instance, `@1` will match all `1.x.x` versions and `@1.2`
  will match all `1.2.x` versions.
- Zero bounds, which `Pkg` rejects, mean what they say: `@0.0.0` matches data
  sets with no version (which count as `0.0.0`), and `@<0` matches nothing.

As in `Pkg`, a comma-separated list of specifiers is a union: `iris@~1.2, 2`
matches any version that `~1.2` or `2` matches.

The following are all valid identifiers, using the `@`-shorthand:
```
iris@1
iris@~1
iris@>=2
iris@latest
```

When multiple data sets match the version specification, the one with the
highest matching version is used.
"""
const VERSIONS_PLUGIN =
    Plugin("versions", [
        versions_ident_parse_a,
        versions_refine_a,
        versions_ident_string_a,
        versions_do_lint_a])

# ---------------
# Default linters
# ---------------

function lint_versions(obj::DataSet, ::Val{:valid_version})
    if haskey(obj.parameters, "version")
        if get(obj, "version") isa Number
            LintItem(obj, :warning, :valid_version,
                     "Version number ($(get(obj, "version"))) should be provided as a string",
                     function (::IO, li::LintItem)
                         li.source.parameters["version"] =
                             string(li.source.parameters["version"])
                         true
                     end, true)
        elseif isnothing(tryparse(VersionNumber, string(get(obj, "version"))))
            LintItem(obj, :warning, :valid_version,
                     "Invalid version number $(sprint(show, get(obj, "version")))",
                     lint_fix_version)
        end
    end
end

function lint_fix_version(io::IO, lintitem::LintItem{DataSet})
    print(io, "  Version: ")
    newversion = readline(io)
    while isnothing(tryparse(VersionNumber, newversion))
        print(io, "  Version (X.Y.Z): ")
        newversion = readline(io)
    end
    lintitem.source.parameters["version"] = newversion
    true
end
