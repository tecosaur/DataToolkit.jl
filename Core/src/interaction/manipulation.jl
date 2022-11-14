# ------------------
# Initialisation
# ------------------

"""
    init(name::Union{AbstractString, Missing},
         path::Union{AbstractString, Nothing};
         uuid::UUID=uuid4(), plugins::Vector{String}=DEFAULT_PLUGINS,
         write::Bool=true, addtostack::Bool=true, quiet::Bool=false)
Create a new data collection.

This can be an in-memory data collection, when `path` is set to `nothing`, or a
collection which correspands to a Data TOML file, in which case `path` should be
set to either a path to a .toml file or a directory in which a Data.toml file
should be placed.

When `path` is a string and `write` is set, the data collection file will be
immedately written, overwriting any existing file at the path.

When `addtostack` is set, the data collection will also be added to the top of
the data collection stack.

Unless `quiet` is set, a message will be send to stderr reporting successful
creating of the data collection file.

### Example

```julia-repl
julia> init("test", "/tmp/test/Data.toml")
```
"""
function init(name::Union{AbstractString, Missing},
              path::Union{AbstractString, Nothing};
              uuid::UUID=uuid4(), plugins::Vector{String}=DEFAULT_PLUGINS,
              write::Bool=true, addtostack::Bool=true, quiet::Bool=false)
    if !endswith(path, ".toml")
        path = joinpath(path, "Data.toml")
    end
    if ismissing(name)
        name = if !isnothing(Base.active_project(false))
            Base.active_project(false) |> dirname |> basename
        else
            something(path, string(gensym("unnamed"))[3:end]) |>
                dirname |> basename
        end
    end
    newcollection = DataCollection(LATEST_DATA_CONFIG_VERSION, name, uuid,
                                   plugins, Dict{String, Any}(), DataSet[],
                                   path, DataAdviceAmalgamation(plugins),
                                   Main)
    !isnothing(path) && write && Base.write(newcollection)
    addtostack && pushfirst!(STACK, newcollection)
    if !quiet
        if !isnothing(path)
            printstyled(stderr, " ✓ Created new data collection '$name' at $path\n", color=:green)
        else
            printstyled(stderr, " ✓ Created new in-memory data collection '$name'\n", color=:green)
        end
    end
    newcollection
end

# ------------------
# Plugins
# ------------------

"""
    plugin_add(plugins::Vector{<:AbstractString}, collection::DataCollection=first(STACK);
               quiet::Bool=false)
Add `plugins` not currently used in `collection` to `collection`'s plugins, and
write the collection.

Unless `quiet` is a set a sucess message is printed.
"""
function plugin_add(plugins::Vector{<:AbstractString}, collection::DataCollection=first(STACK);
                    quiet::Bool=false)
    new_plugins = setdiff(plugins, collection.plugins)
    append!(collection.plugins, new_plugins)
    write(collection)
    quiet || printstyled(" ✓ Added plugins: $(join(''' .* new_plugins .* ''', ", "))\n", color=:green)
end

"""
    plugin_remove(plugins::Vector{<:AbstractString}, collection::DataCollection=first(STACK);
                  quiet::Bool=false)
Remove all `plugins` currently used in `collection`, and write the collection.

Unless `quiet` is a set a sucess message is printed.
"""
function plugin_remove(plugins::Vector{<:AbstractString}, collection::DataCollection=first(STACK);
                       quiet::Bool=false)
    rem_plugins = intersect(plugins, collection.plugins)
    deleteat!(collection.plugins, indexin(rem_plugins, collection.plugins))
    write(collection)
    quiet || printstyled(" ✓ Removed plugins: $(join(''' .* rem_plugins .* ''', ", "))\n", color=:green)
end

"""
    plugin_info(plugin::AbstractString; quiet::Bool=false)
Fetch the documentation of `plugin`, or return `nothing` if documentation could
not be fetched.

If `quiet` is not set warning messages will be ommited when no documentation
could be fetched.
"""
function plugin_info(plugin::AbstractString; quiet::Bool=false)
    if plugin ∉ getfield.(PLUGINS, :name)
        if !quiet
            printstyled(" ! ", color=:red, bold=true)
            println("The plugin '$plugin' is not currently loaded")
        end
    else
        documentation = get(PLUGINS_DOCUMENTATION, plugin, nothing)
        if !isnothing(documentation)
            quiet || printstyled("  The $plugin plugin\n\n", color=:blue, bold=true)
            documentation
        else
            if !quiet
                printstyled(" ! ", color=:yellow, bold=true)
                println("The plugin '$plugin' has no documentation (naughty plugin!)")
            end
        end
    end
end

"""
    plugin_list(; collection::DataCollection=first(STACK), quiet::Bool=false)
Obtain a list of plugins used in `collection`.

`quiet` is unused but accepted as an argument for the sake of consistency.
"""
plugin_list(; collection::DataCollection=first(STACK), quiet::Bool=false) =
    collection.plugins
