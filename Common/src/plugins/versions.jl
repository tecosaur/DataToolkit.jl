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
            Identifier(ident.collection, name, ident.type, ident.parameters)
        else
            ident
        end
    end
    (extractversion!, f, (ident,))
end

function pkg_semver_spec end # Implemented in `../../ext/PkgExt.jl`

"""
    versions_refine_a( <refine(datasets::Vector{DataSet}, ident::Identifier, ignoreparams::Vector{String})> )

Advice that refines the data sets by version.

Part of `VERSIONS_PLUGIN`.
"""
function versions_refine_a(f::typeof(refine), datasets::Vector{DataSet}, ident::Identifier, ignoreparams::Vector{String})
    @require Pkg
    if haskey(ident.parameters, "version")
        versions = map(
            ds -> @something(if haskey(ds.parameters, "version")
                                    tryparse(VersionNumber,
                                            string(ds.parameters["version"]))
                                end,
                                v"0"),
            datasets)
        if ident.parameters["version"] == "latest"
            datasets = datasets[versions .== maximum(versions)]
        else
            requirement = invokelatest(
                pkg_semver_spec, String(ident.parameters["version"]))
            validmask = [v ∈ requirement for v in versions]
            datasets = if any(validmask)
                maxvalid = maximum(versions[validmask])
                datasets[versions .== maxvalid]
            else
                DataSet[]
            end
        end
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

The version matching re-uses machinery from `Pkg`, and so all
[`Pkg`-style version specifications](https://pkgdocs.julialang.org/v1/compatibility/#Version-specifier-format)
are supported. In addition to this, one can simply request the "latest" version.

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
                     function (li::LintItem)
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

function lint_fix_version(lintitem::LintItem{DataSet})
    newversion = prompt("  Version: ")
    while isnothing(tryparse(VersionNumber, newversion))
        newversion = prompt("  Version (X.Y.Z): ")
    end
    lintitem.source.parameters["version"] = newversion
    true
end
