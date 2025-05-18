# ------------------
# Stack management
# ------------------

"""
    stack_index(ident::Union{Int, String, UUID, DataCollection}; quiet::Bool=false)

Obtain the index of the data collection identified by `ident` on the stack,
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

function stack_index(collection::DataCollection; quiet::Bool = false)
    idx = findfirst(STACK .=== Ref(collection))
    isnothing(idx) && return idx
    if !quiet
        printstyled(" ! ", color=:red)
        println("Could not find '$collection' in the stack")
    end
end

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

function collection_reinit!(collection::DataCollection,
                           spec::Dict{String, Any} = convert(Dict, collection);
                           plugins::Vector{String} = collection.plugins)
    if collection.plugins !== plugins
        empty!(collection.plugins)
        append!(collection.plugins, plugins)
        empty!(collection.advise.advisors)
        empty!(collection.advise.plugins_wanted)
        append!(collection.advise.plugins_wanted, plugins)
        empty!(collection.advise.plugins_used)
        reinit(collection.advise)
    end
    empty!(collection.parameters)
    for (k, v) in get(spec, "config", Dict{String, Any}())::Dict{String, Any}
        collection.parameters[k] = v
    end
    for reservedname in DATA_CONFIG_RESERVED_ATTRIBUTES[:collection]
        delete!(spec, reservedname)
    end
    empty!(collection.datasets)
    for (name, dspecs) in spec
        for dspec in if dspecs isa Vector dspecs else [dspecs] end
            push!(collection.datasets, DataSet(collection, name, dspec))
        end
    end
    reconstructed = @advise identity(collection)
    # We need to account for the possibility that `collection`
    # may have been modified out-of-place by advice.
    if reconstructed.version != collection.version
        collection.version = reconstructed.version
    end
    if reconstructed.name != collection.name
        collection.name = reconstructed.name
    end
    if reconstructed.uuid != collection.uuid
        @warn "Cannot change collection UUID: $collection.uuid (current) != $reconstructed.uuid (new)"
    end
    if reconstructed.plugins !== collection.plugins
        empty!(collection.plugins)
        append!(collection.plugins, reconstructed.plugins)
    end
    if reconstructed.parameters !== collection.parameters
        empty!(collection.parameters)
        for (k, v) in reconstructed.parameters
            collection.parameters[k] = v
        end
    end
    if reconstructed.datasets !== collection.datasets
        @warn "Collection dataset replacement is unimplemented, skipped"
    end
    if reconstructed.source != collection.source
        collection.source = reconstructed.source
    end
    if reconstructed.mod != collection.mod
        @warn "Cannot change collection module: $collection.mod (current) != $reconstructed.mod (new)"
    end
    collection
end

"""
    plugin_add!([collection::DataCollection=first(STACK)], plugins::Vector{<:AbstractString};
               quiet::Bool=false)

Return a variation of `collection` with all `plugins` not currently used added
to the plugin list.

Unless `quiet` is a set an informative message is printed.

!!! warning "Side effects"
    The new `collection` is written, if possible.

    Should `collection` be part of `STACK`, the stack entry is updated in-place.
"""
function plugin_add!(collection::DataCollection, plugins::Vector{<:AbstractString};
                    quiet::Bool=false)
    new_plugins = setdiff(plugins, collection.plugins)
    if isempty(new_plugins)
        if !quiet
            printstyled(" i", color=:cyan, bold=true)
            println(" No new plugins added")
        end
    else
        # It may seem overcomplicated to:
        # 1. Convert `collection` to a Dict
        # 2. Modify the "plugin" list there
        # 3. Convert back
        # instead of simply `push!`-ing to the `plugins` field
        # of `collection`, however this is necessary to avoid
        # asymmetric advice triggering by the plugins in question.
        spec = convert(Dict, collection)
        spec["plugins"] = append!(get(spec, "plugins", String[]), new_plugins)
        sort!(spec["plugins"])
        collection_reinit!(collection, spec; plugins = spec["plugins"])
        iswritable(collection) && write(collection)
        if !quiet
            printstyled(" +", color=:light_green, bold=true)
            print(" Added plugins: ")
            printstyled(join(new_plugins, ", "), '\n', color=:green)
        end
    end
    collection
end

function plugin_add!(plugins::Vector{<:AbstractString}; quiet::Bool=false)
    !isempty(STACK) || throw(EmptyStackError())
    plugin_add!(first(STACK), plugins; quiet)
end

"""
    plugin_remove!([collection::DataCollection=first(STACK)], plugins::Vector{<:AbstractString};
                  quiet::Bool=false)

Return a variation of `collection` with all `plugins` currently used removed
from the plugin list.

Unless `quiet` is a set an informative message is printed.

!!! warning "Side effects"
    The new `collection` is written, if possible.

    Should `collection` be part of `STACK`, the stack entry is updated in-place.
"""
function plugin_remove!(collection::DataCollection, plugins::Vector{<:AbstractString};
                        quiet::Bool=false)
    rem_plugins = intersect(plugins, collection.plugins)
    if isempty(rem_plugins)
        if !quiet
            printstyled(" ! ", color=:yellow, bold=true)
            println("No plugins removed, as $(join(plugins, ", ", ", and ")) were never used to begin with")
        end
    else
        # It may seem overcomplicated to:
        # 1. Convert `collection` to a Dict
        # 2. Modify the "plugin" list there
        # 3. Convert back
        # instead of simply modifying the `plugins` field
        # of `collection`, however this is necessary to avoid
        # asymmetric advice triggering by the plugins in question.
        spec = convert(Dict, collection)
        spec["plugins"] = setdiff(get(spec, "plugins", String[]), rem_plugins)
        sort!(spec["plugins"])
        collection_reinit!(collection, spec; plugins = spec["plugins"])
        iswritable(collection) && write(collection)
        if !quiet
            printstyled(" -", color=:light_red, bold=true)
            print(" Removed plugins: ")
            printstyled(join(rem_plugins, ", "), '\n', color=:green)
        end
    end
    collection
end

function plugin_remove!(plugins::Vector{<:AbstractString}; quiet::Bool=false)
    !isempty(STACK) || throw(EmptyStackError())
    plugin_remove!(first(STACK), plugins; quiet)
end

"""
    plugin_info(plugin::AbstractString; quiet::Bool=false)

Fetch the documentation of `plugin`, or return `nothing` if documentation could
not be fetched.

If `quiet` is not set warning messages will be omitted when no documentation
could be fetched.
"""
function plugin_info(plugin::AbstractString; quiet::Bool=false)
    if plugin ∉ (p.name for p in PLUGINS)
        if !quiet
            printstyled(" ! ", color=:red, bold=true)
            println("The plugin '$plugin' is not currently loaded")
        end
    else
        documentation = get(PLUGINS_DOCUMENTATION, plugin, nothing)
        if !isnothing(documentation)
            quiet || printstyled("  The $plugin plugin\n\n", color=:blue, bold=true)
            if documentation isa Base.Docs.DocStr
                Base.Docs.parsedoc(documentation)
            elseif documentation isa Base.Docs.Binding
                Base.Docs.doc(documentation)
            else
                documentation
            end
        else
            if !quiet
                printstyled(" ! ", color=:yellow, bold=true)
                println("The plugin '$plugin' has no documentation (naughty plugin!)")
            end
        end
    end
end

"""
    plugin_list(collection::DataCollection=first(STACK); quiet::Bool=false)

Obtain a list of plugins used in `collection`.

`quiet` is unused but accepted as an argument for the sake of consistency.
"""
plugin_list(collection::DataCollection=first(STACK); quiet::Bool=false) =
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
function config_get(collection::DataCollection, propertypath::Vector{String}; quiet::Bool=false)
    config = collection.parameters
    for segment in propertypath
        config isa AbstractDict || (config = newdict(String, Nothing, 0);)
        config = get(config, segment, nothing)
        if isnothing(config)
            quiet || printstyled(" unset\n", color=:light_black)
            return nothing
        end
    end
    config
end

config_get(propertypath::Vector{String}; quiet::Bool=false) =
    config_get(first(STACK), propertypath; quiet)

"""
    config_set!([collection::DataCollection=first(STACK)], propertypath::Vector{String}, value::Any;
               quiet::Bool=false)

Return a variation of `collection` with the configuration at `propertypath` set
to `value`.

Unless `quiet` is set, a success message is printed.

!!! warning "Side effects"
    The new `collection` is written, if possible.

    Should `collection` be part of `STACK`, the stack entry is updated in-place.
"""
function config_set!(collection::DataCollection, propertypath::Vector{String}, value::Any;
                     quiet::Bool=false)
    # It may seem like an unnecessary layer of indirection to set
    # the configuration via a Dict conversion of `collection`,
    # however this way any plugin-processing of the configuration
    # will be symmetric (i.e. applied at load and write).
    spec = convert(Dict, collection)
    config = get(spec, "config", newdict(String, Any, 0))
    window = config
    for segment in propertypath[1:end-1]
        if !haskey(window, segment)
            window[segment] = newdict(String, Any, 0)
        end
        window = window[segment]
    end
    window[propertypath[end]] = value
    spec["config"] = config
    collection_reinit!(collection, spec)
    iswritable(collection) && write(collection)
    quiet || printstyled(" ✓ Set $(join(propertypath, '.'))\n", color=:green)
    collection
end

function config_set!(propertypath::Vector{String}, value::Any; quiet::Bool=false)
    !isempty(STACK) || throw(EmptyStackError())
    config_set!(first(STACK), propertypath, value; quiet)
end

"""
    config_unset!([collection::DataCollection=first(STACK)], propertypath::Vector{String};
                  quiet::Bool=false)

Return a variation of `collection` with the configuration at `propertypath`
removed.

Unless `quiet` is set, a success message is printed.

!!! warning "Side effects"
    The new `collection` is written, if possible.

    Should `collection` be part of `STACK`, the stack entry is updated in-place.
"""
function config_unset!(collection::DataCollection, propertypath::Vector{String};
                       quiet::Bool=false)
    # It may seem like an unnecessary layer of indirection to set
    # the configuration via a Dict conversion of `collection`,
    # however this way any plugin-processing of the configuration
    # will be symmetric (i.e. applied at load and write).
    spec = convert(Dict, collection)
    config = get(spec, "config", newdict(String, Any, 0))
    window = config
    for segment in propertypath[1:end-1]
        if !haskey(window, segment)
            window[segment] = Dict{String, Any}()
        end
        window = window[segment]
    end
    delete!(window, propertypath[end])
    spec["config"] = config
    collection_reinit!(collection, spec)
    iswritable(collection) && write(collection)
    quiet || printstyled(" ✓ Unset $(join(propertypath, '.'))\n", color=:green)
    collection
end

function config_unset!(propertypath::Vector{String}; quiet::Bool=false)
    !isempty(STACK) || throw(EmptyStackError())
    config_unset!(first(STACK), propertypath; quiet)
end

# ------------------
# Dataset creation
# ------------------

# See `creation.jl`

# ------------------
# Dataset deletion
# ------------------

"""
    delete!(dataset::DataSet)

Remove `dataset` from its parent collection.
"""
function Base.delete!(dataset::DataSet)
    index = findfirst(d -> d.uuid == dataset.uuid, dataset.collection.datasets)
    isnothing(index) && throw(OrphanDataSet(dataset))
    deleteat!(dataset.collection.datasets, index)
    write(dataset.collection)
end

# ------------------
# Dataset modification
# ------------------

"""
    replace!(dataset::DataSet; [name, uuid, parameters, storage, loaders, writers])

Perform an in-place update of `dataset`, optionally replacing any of the `name`,
`uuid`, `parameters`, `storage`, `loaders`, or `writers` fields.
"""
function Base.replace!(dataset::DataSet;
                       name::String = dataset.name,
                       uuid::UUID = dataset.uuid,
                       parameters::Dict{String, Any} = dataset.parameters,
                       storage::Vector{DataStorage} = dataset.storage,
                       loaders::Vector{DataLoader} = dataset.loaders,
                       writers::Vector{DataWriter} = dataset.writers)
    iswritable(dataset.collection) || throw(ReadonlyCollection(dataset.collection))
    dsindex = findfirst(==(dataset), dataset.collection.datasets)
    !isnothing(dsindex) || throw(OrphanDataSet(dataset))
    replacement = DataSet(dataset.collection, name, uuid, parameters,
                          DataStorage[], DataLoader[], DataWriter[])
    for tf in storage
        push!(replacement.storage, typeof(tf)(replacement, tf.type, tf.priority, tf.parameters))
    end
    for tf in loaders
        push!(replacement.loaders, typeof(tf)(replacement, tf.type, tf.priority, tf.parameters))
    end
    for tf in writers
        push!(replacement.writers, typeof(tf)(replacement, tf.type, tf.priority, tf.parameters))
    end
    dataset.collection.datasets[dsindex] = replacement
end
