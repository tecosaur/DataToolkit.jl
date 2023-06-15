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
                                   path, AdviceAmalgamation(plugins),
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
    plugin_add([collection::DataCollection=first(STACK)], plugins::Vector{<:AbstractString};
               quiet::Bool=false)

Return a variation of `collection` with all `plugins` not currently used added
to the plugin list.

Unless `quiet` is a set an informative message is printed.

!!! warning "Side effects"
    The new `collection` is written, if possible.

    Should `collection` be part of `STACK`, the stack entry is updated in-place.
"""
function plugin_add(collection::DataCollection, plugins::Vector{<:AbstractString};
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
        # asymetric advice trigerring by the plugins in question.
        snapshot = convert(Dict, collection)
        snapshot["plugins"] =
            append!(get(snapshot, "plugins", String[]), new_plugins)
        sort!(snapshot["plugins"])
        newcollection =
            DataCollection(snapshot; path=collection.path, mod=collection.mod)
        if (sindex = findfirst(c -> c === collection, STACK)) |> !isnothing
            STACK[sindex] = newcollection
        end
        iswritable(newcollection) && write(newcollection)
        if !quiet
            printstyled(" +", color=:light_green, bold=true)
            print(" Added plugins: ")
            printstyled(join(new_plugins, ", "), '\n', color=:green)
        end
    end
    newcollection
end

function plugin_add(plugins::Vector{<:AbstractString}; quiet::Bool=false)
    !isempty(STACK) || throw(EmptyStackError())
    plugin_add(first(STACK), plugins; quiet)
end

"""
    plugin_remove([collection::DataCollection=first(STACK)], plugins::Vector{<:AbstractString};
                  quiet::Bool=false)

Return a variation of `collection` with all `plugins` currently used removed
from the plugin list.

Unless `quiet` is a set an informative message is printed.

!!! warning "Side effects"
    The new `collection` is written, if possible.

    Should `collection` be part of `STACK`, the stack entry is updated in-place.
"""
function plugin_remove(collection::DataCollection, plugins::Vector{<:AbstractString};
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
        # asymetric advice trigerring by the plugins in question.
        snapshot = convert(Dict, collection)
        snapshot["plugins"] =
            setdiff(get(snapshot, "plugins", String[]), rem_plugins)
        newcollection =
            DataCollection(snapshot; path=collection.path, mod=collection.mod)
        if (sindex = findfirst(c -> c === collection, STACK)) |> !isnothing
            STACK[sindex] = newcollection
        end
        iswritable(newcollection) && write(newcollection)
        if !quiet
            printstyled(" -", color=:light_red, bold=true)
            print(" Removed plugins: ")
            printstyled(join(rem_plugins, ", "), '\n', color=:green)
        end
    end
    newcollection
end

function plugin_remove(plugins::Vector{<:AbstractString}; quiet::Bool=false)
    !isempty(STACK) || throw(EmptyStackError())
    plugin_remove(first(STACK), plugins; quiet)
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
    config_set([collection::DataCollection=first(STACK)], propertypath::Vector{String}, value::Any;
               quiet::Bool=false)

Return a variation of `collection` with the configuration at `propertypath` set
to `value`.

Unless `quiet` is set, a success message is printed.

!!! warning "Side effects"
    The new `collection` is written, if possible.

    Should `collection` be part of `STACK`, the stack entry is updated in-place.
"""
function config_set(collection::DataCollection, propertypath::Vector{String}, value::Any;
                     quiet::Bool=false)
    # It may seem like an unecessary layer of inderection to set
    # the configuration via a Dict conversion of `collection`,
    # however this way any plugin-processing of the configuration
    # will be symmetric (i.e. applied at load and write).
    snapshot = convert(Dict, collection)
    config = get(snapshot, "config", SmallDict{String, Any}())
    window = config
    for segment in propertypath[1:end-1]
        if !haskey(window, segment)
            window[segment] = SmallDict{String, Any}()
        end
        window = window[segment]
    end
    window[propertypath[end]] = value
    snapshot["config"] = config
    newcollection =
        DataCollection(snapshot; path=collection.path, mod=collection.mod)
    if (sindex = findfirst(c -> c === collection, STACK)) |> !isnothing
        STACK[sindex] = newcollection
    end
    iswritable(newcollection) && write(newcollection)
    quiet || printstyled(" ✓ Set $(join(propertypath, '.'))\n", color=:green)
    newcollection
end

function config_set(propertypath::Vector{String}, value::Any; quiet::Bool=false)
    !isempty(STACK) || throw(EmptyStackError())
    config_set(first(STACK), propertypath, value; quiet)
end

"""
    config_unset([collection::DataCollection=first(STACK)], propertypath::Vector{String};
                  quiet::Bool=false)

Return a variation of `collection` with the configuration at `propertypath`
removed.

Unless `quiet` is set, a success message is printed.

!!! warning "Side effects"
    The new `collection` is written, if possible.

    Should `collection` be part of `STACK`, the stack entry is updated in-place.
"""
function config_unset(collection::DataCollection, propertypath::Vector{String};
                       quiet::Bool=false)
    # It may seem like an unecessary layer of inderection to set
    # the configuration via a Dict conversion of `collection`,
    # however this way any plugin-processing of the configuration
    # will be symmetric (i.e. applied at load and write).
    snapshot = convert(Dict, collection)
    config = get(snapshot, "config", SmallDict{String, Any}())
    window = config
    for segment in propertypath[1:end-1]
        if !haskey(window, segment)
            window[segment] = Dict{String, Any}()
        end
        window = window[segment]
    end
    delete!(window, propertypath[end])
    snapshot["config"] = config
    newcollection =
        DataCollection(snapshot; path=collection.path, mod=collection.mod)
    if (sindex = findfirst(c -> c === collection, STACK)) |> !isnothing
        STACK[sindex] = newcollection
    end
    iswritable(newcollection) && write(newcollection)
    quiet || printstyled(" ✓ Unset $(join(propertypath, '.'))\n", color=:green)
    newcollection
end

function config_unset(propertypath::Vector{String}; quiet::Bool=false)
    !isempty(STACK) || throw(EmptyStackError())
    config_unset(first(STACK), propertypath; quiet)
end

# ------------------
# Dataset creation
# ------------------

"""
    add(::Type{DataSet}, name::String, spec::Dict{String, Any}, source::String="";
        collection::DataCollection=first(STACK), storage::Vector{Symbol}=Symbol[],
        loaders::Vector{Symbol}=Symbol[], writers::Vector{Symbol}=Symbol[],
        quiet::Bool=false)

Create a new DataSet with a `name` and `spec`, and add it to `collection`.  The
data transformers will be constructed with each of the backends listed in
`storage`, `loaders`, and `writers` from `source`. If the symbol `*` is given,
all possible drivers will be searched and the highest priority driver avilible
(according to `createpriority`) used. Should no transformer of the specified
driver and type exist, it will be skipped.
"""
function add(::Type{DataSet}, name::String, spec::Dict{String, Any}, source::String="";
             collection::DataCollection=first(STACK),
             storage::Vector{Symbol}=Symbol[], loaders::Vector{Symbol}=Symbol[],
             writers::Vector{Symbol}=Symbol[], quiet::Bool=false)
    spec["uuid"] = uuid4()
    dataset = @advise fromspec(DataSet, collection, name, spec)
    for (transformer, slot, drivers) in ((DataStorage, :storage, storage),
                                         (DataLoader, :loaders, loaders),
                                         (DataWriter, :writers, writers))
        for driver in drivers
            dt = create(transformer, driver, source, dataset)
            if isnothing(dt)
                printstyled(" ! ", color=:yellow, bold=true)
                println("Failed to create '$driver' $(string(nameof(transformer))[5:end])")
            else
                push!(getproperty(dataset, slot), dt)
            end
        end
    end
    push!(collection.datasets, dataset)
    iswritable(collection) && write(collection)
    quiet || printstyled(" ✓ Created '$name' ($(dataset.uuid))\n ", color=:green)
    dataset
end

"""
    create(T::Type{<:AbstractDataTransformer}, source::String, dataset::DataSet)

If `source`/`dataset` can be used to construct a data transformer of type `T`,
do so and return it. Otherwise return `nothing`.

Specific transformers should implement specialised forms of this function, that
either return `nothing` to indicate that it is not applicable, or a "create spec
form". A "create spec form" is simply a list of `key::String => value` entries,
giving properties of the to-be-created transformer, e.g.

```
["foo" => "bar",
 "baz" => 2]
```

In addition to accepting TOML-representable values, a `NamedTuple` value can
be given that specifies an interactive prompt to put to the user.

```
(; prompt::String = "\$key",
   type::Type{String or Bool or <:Number} = String,
   default::type = false or "",
   optional::Bool = false,
   skipvalue::Any = nothing,
   post::Function = identity)
```

The value can also be a `Function` that takes the current specification as an
argument and returns a TOML-representable value or `NamedTuple`.

Lastly `true`/`false` can be returned as a convenient way of simply indicating
whether an empty (no parameters) driver should be created.
"""
create(T::Type{<:AbstractDataTransformer}, source::String, ::DataSet) =
    create(T::Type{<:AbstractDataTransformer}, source)
create(::Type{<:AbstractDataTransformer}, ::String) = nothing

"""
    createpriority(T::Type{<:AbstractDataTransformer})

The priority with which a transformer of type `T` should be created.
This can be any integer, but try to keep to -100–100 (see `create`).
"""
createpriority(T::Type{<:AbstractDataTransformer}) = 0

"""
    create(T::Type{<:AbstractDataTransformer}, driver::Symbol, source::String, dataset::DataSet;
           minpriority::Int=-100, maxpriority::Int=100)

Create a new `T` with driver `driver` from `source`/`dataset`.

If `driver` is the symbol `*` then all possible drivers are checked and the
highest priority (according to `createpriority`) valid driver used. Drivers with
a priority outside `minpriority`–`maxpriority` will not be considered.

The created data transformer is returned, unless the given `driver` is not
valid, in which case `nothing` is returned instead.
"""
function create(T::Type{<:AbstractDataTransformer}, driver::Symbol, source::String, dataset::DataSet;
                minpriority::Int=-100, maxpriority::Int=100)
    T ∈ (DataStorage, DataLoader, DataWriter) ||
        throw(ArgumentError("T=$T should be an driver-less Data{Storage,Loader,Writer}"))
    function process_spec(spec::Vector, driver::Symbol)
        final_spec = Dict{String, Any}()
        function expand_value(key::String, value::Any)
            if value isa Function
                value = value(final_spec)
            end
            final_value = if value isa TOML.Internals.Printer.TOMLValue
                value
            elseif value isa NamedTuple
                type = get(value, :type, String)
                vprompt = " $(string(nameof(T))[5])($driver) " *
                    get(value, :prompt, "$key: ")
                result = if type == Bool
                    confirm_yn(vprompt, get(value, :default, false))
                elseif type == String
                    res = prompt(vprompt, get(value, :default, "");
                                 allowempty = get(value, :optional, false))
                    if !isempty(res) res end
                elseif type <: Number
                    parse(type, prompt(vprompt, string(get(value, :default, zero(type)))))
                end |> get(value, :post, identity)
                if get(value, :optional, false) && get(value, :skipvalue, nothing) === true && result
                else
                    result
                end
            end
            if !isnothing(final_value)
                final_spec[key] = final_value
            end
        end
        for (key, value) in spec
            expand_value(key, value)
        end
        final_spec["driver"] = string(driver)
        final_spec
    end
    if driver == :*
        alldrivers = if T == DataStorage
            vcat(methods(storage), methods(getstorage))
        elseif T == DataLoader
            methods(load)
        elseif T == DataWriter
            methods(save)
        end |>
            ms -> map(f -> Base.unwrap_unionall(
                Base.unwrap_unionall(f.sig).types[2]).parameters[1], ms) |>
            ds -> filter(d -> d isa Symbol, ds) |> unique |>
            ds -> sort(ds, by=driver -> createpriority(T{driver})) |>
            ds -> filter(driver ->
                minpriority <= createpriority(T{driver}) <= maxpriority, ds)
        for drv in alldrivers
            spec = create(T{drv}, source, dataset)
            spec isa Bool && (spec = ifelse(spec, [], nothing))
            if !isnothing(spec)
                return @advise fromspec(T, dataset, process_spec(spec, drv))
            end
        end
    else
        spec = create(T{driver}, source, dataset)::Union{Bool, Vector, Nothing}
        spec isa Bool && (spec = ifelse(spec, [], nothing))
        if !isnothing(spec)
            return @advise fromspec(T, dataset, process_spec(spec, driver))
        end
    end
end

# ------------------
# Dataset deletion
# ------------------

"""
    delete!(dataset::DataSet)

Remove `dataset` from its parent collection.
"""
function Base.delete!(dataset::DataSet)
    index = findfirst(d -> d.uuid == dataset.uuid, dataset.collection.datasets)
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
    for (tfield, transformers) in zip((:storage, :loaders, :writers),
                                      (storage, loaders, writers))
        for transformer in transformers
            push!(getfield(replacement, tfield),
                  typeof(transformer)(replacement, transformer.type,
                                      transformer.priority, transformer.parameters))
        end
    end
    dataset.collection.datasets[dsindex] = replacement
end
