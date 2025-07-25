# [Memorise](@id plugin-memorise)

!!! info "Using this plugin"
    To use the plugin, either modify the `plugins` entry of the
    collection's [Data.toml](@extref) to include `"memorise"`, or use the Data
    REPL's [`plugin add`](@extref repl-plugin-add)/[`plugin remove`](@extref
    repl-plugin-remove) subcommands.

Cache the results of data loaders in memory. This requires `(dataset::DataSet, as::Type)` to consistently identify the same loaded information.

### Enabling caching of a dataset

```toml
[[mydata]]
memorise = true
```

`memorise` can be a boolean value, a type that should be memorised, or a list of types to be memorised.


