# [Defaults](@id plugin-defaults)

!!! info "Using this plugin"
    To use the plugin, either modify the `plugins` entry of the
    collection's [Data.toml](@extref) to include `"defaults"`, or use the Data
    REPL's [`plugin add`](@extref repl-plugin-add)/[`plugin remove`](@extref
    repl-plugin-remove) subcommands.

Apply default values from the "defaults" data collection property. This works with both DataSets and DataTransformers.

### Default DataSet property

```toml
[config.defaults]
description="Oh no, nobody bothered to describe this dataset."
```

### Default DataTransformer property

This is scoped to a particular transformer, and a particular driver. One may also affect all drivers with the special "all drivers" key `_`. Specific-driver defaults always override all-driver defaults.

```toml
[config.defaults.storage._]
priority=0

[config.defaults.storage.filesystem]
priority=2
```


