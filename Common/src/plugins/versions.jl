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
const VERSIONS_PLUGIN = Plugin("versions", [
    function (post::Function, f::typeof(parse), ::Type{Identifier}, ident::AbstractString)
        function extractversion!(ident::Identifier)
            if ident.dataset isa AbstractString && count('@', ident.dataset) == 1
                name, version = split(ident.dataset, '@')
                ident.parameters["version"] = version
                Identifier(ident.collection, name, ident.type, ident.parameters)
            else
                ident
            end
        end
        (post ∘ extractversion!, f, (Identifier, ident))
    end,
    function (post::Function, f::typeof(refine),
              datasets::Vector{DataSet}, ident::Identifier, ignoreparams::Vector{String})
        @import Pkg.Versions.semver_spec
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
                requirement = semver_spec(String(ident.parameters["version"]))
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
        (post, f, (datasets, ident, ignoreparams))
    end,
    function (post::Function, f::typeof(string), ident::Identifier)
        if haskey(ident.parameters, "version")
            ident = Identifier(
                ident.collection,
                string(ident.dataset, '@',
                        ident.parameters["version"]),
                ident.type,
                delete!(copy(ident.parameters), "version"))
        end
        (post, f, (ident,))
    end
])
