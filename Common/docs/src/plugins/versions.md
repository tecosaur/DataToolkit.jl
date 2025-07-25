# [Versions](@id plugin-versions)

!!! info "Using this plugin"
    To use the plugin, either modify the `plugins` entry of the
    collection's [Data.toml](@extref) to include `"versions"`, or use the Data
    REPL's [`plugin add`](@extref repl-plugin-add)/[`plugin remove`](@extref
    repl-plugin-remove) subcommands.

Give data sets versions, and identify them by version.

### Giving data sets a version

Multiple editions of a data set can be described by using the same name, but setting the `version` parameter to differentiate them.

For instance, say that Ronald Fisher released a second version of the "Iris" data set, with more flowers. We could specify this as:

```toml
[[iris]]
version = "1"
...

[[iris]]
version = "2"
...
```

### Matching by version

Version matching is done via the `Identifier` parameter `"version"`. As shorthand, instead of providing the `"version"` parameter manually, the version can be tacked onto the end of an identifier with `@`, e.g. `iris@1` or `iris@2`.

The version matching re-uses machinery from `Pkg`, and so all [`Pkg`-style version specifications](https://pkgdocs.julialang.org/v1/compatibility/#Version-specifier-format) are supported, with two notable differences:

  * In addition to numeric versioning, you can just ask for the "latest" version
  * Numeric versions with no explicit scheme are matched up to the level of granularity explicitly provided. For instance, `@1` will match all `1.x.x` versions and `@1.2` will match all `1.2.x` versions.

The following are all valid identifiers, using the `@`-shorthand:

```
iris@1
iris@~1
iris@>=2
iris@latest
```

When multiple data sets match the version specification, the one with the highest matching version is used.


