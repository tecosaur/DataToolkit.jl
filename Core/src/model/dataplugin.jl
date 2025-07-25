"""
    @dataplugin plugin_variable
    @dataplugin plugin_variable :default

Register the plugin given by the variable `plugin_variable`, along with its
documentation (fetched by `@doc`). Should `:default` be given as the second
argument the plugin is also added to the list of default plugins.

This effectively serves as a minor, but appreciable, convenience for the
following pattern:

```julia
push!(PLUGINS, myplugin)
PLUGINS_DOCUMENTATION[myplugin.name] = @doc myplugin
push!(DEFAULT_PLUGINS, myplugin.name) # when also adding to defaults
```
"""
macro dataplugin(pluginvar::Symbol)
    quote
        push!(PLUGINS, $(esc(pluginvar)))
        PLUGINS_DOCUMENTATION[$(esc(pluginvar)).name] =
            Base.Docs.Binding(@__MODULE__, $(QuoteNode(pluginvar)))
    end
end

macro dataplugin(pluginvar::Symbol, usebydefault::QuoteNode)
    quote
        push!(PLUGINS, $(esc(pluginvar)))
        PLUGINS_DOCUMENTATION[$(esc(pluginvar)).name] =
            Base.Docs.Binding(@__MODULE__, $(QuoteNode(pluginvar)))
        $(if usebydefault.value == :default
              :(push!(DEFAULT_PLUGINS, $(esc(pluginvar)).name))
          end)
    end
end
