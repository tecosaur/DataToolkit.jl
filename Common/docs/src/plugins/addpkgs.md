# [AddPkgs](@id plugin-addpkgs)

!!! info "Using this plugin"
    To use the plugin, either modify the `plugins` entry of the
    collection's [Data.toml](@extref) to include `"addpkgs"`, or use the Data
    REPL's [`plugin add`](@extref repl-plugin-add)/[`plugin remove`](@extref
    repl-plugin-remove) subcommands.

Register required packages of the Data Collection that needs them.

When using `DataToolkit.@addpkgs` in an interactive session, the named packages will be automatically added to the Data.toml of applicable currently-loaded data collections — avoiding the nead to manually look up the package's UUID and edit the configuration yourself.

### Example usage

```toml
[config.packages]
CSV = "336ed68f-0bac-5ca0-87d4-7b16caf5d00b"
```

With the above configuration and this plugin, upon loading the data collection, the CSV package will be registered under the data collection's module.


