"""
Register required packages of the Data Collection that needs them.

When using `DataToolkit.@addpkgs` in an interactive session, the named packages
will be automatically added to the Data.toml of applicable currently-loaded data
collections — avoiding the nead to manually look up the package's UUID and edit
the configuration yourself.

### Example usage

```toml
[config.packages]
CSV = "336ed68f-0bac-5ca0-87d4-7b16caf5d00b"
```

With the above configuration and this plugin, upon loading the data collection,
the CSV package will be registered under the data collection's module.
"""
const ADDPKGS_PLUGIN =
    Plugin("addpkgs",
           [function (f::typeof(identity), dc::DataCollection)
                pkgs = @getparam dc."packages"::SmallDict{String, Any}
                for (name, uuid_str) in pkgs
                    uuid = tryparse(UUID, uuid_str)
                    if isnothing(uuid)
                        @warn "Unable to register $name [$uuid_str], invalid UUID"
                    else
                        DataToolkitBase.addpkg(
                            dc.mod, Symbol(name), uuid)
                    end
                end
                (f, (dc,))
            end])
