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
# Stack management
# ------------------

"""
    stack_index(ident::Union{Int, String, UUID, DataCollection}; quiet::Bool=false)
Obtai the index of the data collection identified by `ident` on the stack,
if it is present. If it is not found, `nothing` is returned and unless `quiet`
is set a warning is printed.
"""
function stack_index(ident::Union{Int, String, UUID}; quiet::Bool=false)
    if ident isa Int
        if ident in axes(STACK, 1)
            ident
        end
    elseif ident isa String
        findfirst(c -> c.name == ident, STACK)
    elseif ident isa UUID
        findfirst(c -> c.uuid == ident, STACK)
    elseif !quiet
        printstyled(" ! ", color=:red)
        println("Could not find '$ident' in the stack")
    end
end

stack_index(collection::DataCollection) = findfirst(STACK .=== Ref(collection))

"""
    stack_move(ident::Union{Int, String, UUID, DataCollection}, shift::Int; quiet::Bool=false)
Find `ident` in the data collection stack, and shift its position by `shift`,
returning the new index. `shift` is clamped so that the new index lies within
STACK.

If `ident` could not be resolved, then `nothing` is returned and unless `quiet`
is set a warning is printed.
"""
function stack_move(ident::Union{Int, String, UUID, DataCollection}, shift::Int; quiet::Bool=false)
    current_index = stack_index(ident; quiet)
    if !isnothing(current_index)
        collection = STACK[current_index]
        new_index = clamp(current_index + shift, 1, length(STACK))
        if new_index == current_index
            quiet || printstyled(" ✓ '$(collection.name)' already at #$current_index\n", color=:green)
        else
            deleteat!(STACK, current_index)
            insert!(STACK, new_index, collection)
            quiet || printstyled(" ✓ Moved '$(collection.name)': #$current_index → #$new_index\n", color=:green)
        end
        new_index
    end
end

"""
    stack_remove!(ident::Union{Int, String, UUID, DataCollection}; quiet::Bool=false)
Find `ident` in the data collection stack and remove it from the stack,
returning the index at which it was found.

If `ident` could not be resolved, then `nothing` is returned and unless `quiet`
is set a warning is printed.
"""
function stack_remove!(ident::Union{Int, String, UUID, DataCollection}; quiet::Bool=false)
    index = stack_index(ident; quiet)
    if !isnothing(index)
        name = STACK[index].name
        deleteat!(STACK, index)
        quiet || printstyled(" ✓ Deleted $name\n", color=:green)
        index
    end
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

# ------------------
# Configuration
# ------------------

"""
    config_get(propertypath::Vector{String};
               collection::DataCollection=first(STACK), quiet::Bool=false)
Obtain the configuration value at `propertypath` in `collection`.

When no value is set, `nothing` is returned instead and if `quiet` is unset
"unset" is printed.
"""
function config_get(propertypath::Vector{String};
                    collection::DataCollection=first(STACK), quiet::Bool=false)
    config = collection.parameters
    for segment in propertypath
        config = get(config, segment, nothing)
        if isnothing(config)
            quiet || printstyled(" unset\n", color=:light_black)
            return nothing
        end
    end
    config
end

"""
    config_set!(propertypath::Vector{String}, value::Any;
                collection::DataCollection=first(STACK), quiet::Bool=false)
Set the configuration at `propertypath` in `collection` to `value`.

Unless `quiet` is set, a success message is printed.
"""
function config_set!(propertypath::Vector{String}, value::Any;
                     collection::DataCollection=first(STACK), quiet::Bool=false)
    config = collection.parameters
    for segment in propertypath[1:end-1]
        if !haskey(config, segment)
            config[segment] = Dict{String, Any}()
        end
        config = config[segment]
    end
    config[propertypath[end]] = value
    write(collection)
    quiet || printstyled(" ✓ Set $(join(propertypath, '.'))\n", color=:green)
end

"""
    config_unset!(propertypath::Vector{String};
                  collection::DataCollection=first(STACK), quiet::Bool=false)
Unset the configuration at `propertypath` in `collection`.

Unless `quiet` is set, a success message is printed.
"""
function config_unset!(propertypath::Vector{String};
                       collection::DataCollection=first(STACK), quiet::Bool=false)
    config = collection.parameters
    for segment in propertypath[1:end-1]
        if !haskey(config, segment)
            config[segment] = Dict{String, Any}()
        end
        config = config[segment]
    end
    delete!(config, propertypath[end])
    write(collection)
    quiet || printstyled(" ✓ Unset $(join(propertypath, '.'))\n", color=:green)
end
