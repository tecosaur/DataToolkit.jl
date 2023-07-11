"""
    plugin_add(input::AbstractString)
Parse and call the repl-format plugin add command `input`.

`input` should consist of a list of plugin names.
"""
function plugin_add(input::AbstractString)
    confirm_stack_first_writable() || return nothing
    plugins = split(input, r", *| +")
    nonexistant = filter(p -> p ∉ getfield.(PLUGINS, :name), plugins)
    if !isempty(nonexistant)
        printstyled(" ! ", color=:yellow)
        println("Warning: the plugins $(join(nonexistant, ", ", ", and ")) are not known to exist")
        if !confirm_yn(" Do you wish to continue anyway?")
            return nothing
        end
    end
    DataToolkitBase.plugin_add(plugins)
    nothing
end

"""
    plugin_remove(input::AbstractString)
Parse and call the repl-format plugin removal command `input`.

`input` should consist of a list of plugin names.
"""
function plugin_remove(input::AbstractString)
    confirm_stack_first_writable() || return nothing
    plugins = split(input, r", *| +")
    DataToolkitBase.plugin_remove(plugins)
    nothing
end

"""
    plugin_edit(::AbstractString)
Interactively edit the set of plugins used.
"""
function plugin_edit(::AbstractString)
    confirm_stack_first_writable() || return nothing
    original_plugins = copy(first(STACK).plugins)
    availible_plugins = union(getfield.(PLUGINS, :name), first(STACK).plugins)
    menu = REPL.TerminalMenus.MultiSelectMenu(
        availible_plugins,
        selected=indexin(first(STACK).plugins, availible_plugins),
        checked = if get(stdout, :color, false)
            string('[', Base.text_colors[REPL_USER_INPUT_COLOUR],
                    'X',
                    Base.text_colors[REPL_QUESTION_COLOR],
                    ']')
        else "X" end)
    selected_plugins = availible_plugins[REPL.TerminalMenus.request(
        if get(stdout, :color, false)
            Base.text_colors[REPL_QUESTION_COLOR]
        else "" end *
            " Select plugins to use:",
        menu) |> collect]
    added_plugins = setdiff(selected_plugins, original_plugins)
    removed_plugins = setdiff(original_plugins, selected_plugins)
    # See commentary in `DataToolkitBase.add_plugin` for why
    # we edit the plugin list via a Dict conversion.
    let collection = first(STACK)
        snapshot = convert(Dict, collection)
        snapshot["plugins"] = sort(selected_plugins)
        newcollection =
            DataCollection(snapshot; path=collection.path, mod=collection.mod)
        STACK[begin] = newcollection
        iswritable(newcollection) && write(newcollection)
    end
    if isempty(added_plugins) && isempty(removed_plugins)
        printstyled(" No change to plugins\n", color=:green)
    else
        if !isempty(added_plugins)
            printstyled(" +", color=:light_green, bold=true)
            print(" Added plugins: ")
            printstyled(join(added_plugins, ", "), '\n', color=:green)
        end
        if !isempty(removed_plugins)
            printstyled(" -", color=:light_red, bold=true)
            print(" Removed plugins: ")
            printstyled(join(removed_plugins, ", "), '\n', color=:green)
        end
    end
end

"""
    plugin_list(input::AbstractString)
Parse and call the repl-format plugin list command `input`.

`input` should either be empty or '-a'/'--availible'.
"""
function plugin_list(input::AbstractString)
    used_plugins = if isempty(STACK) String[] else first(STACK).plugins end
    plugins = if strip(input) in ("-a", "--availible")
        getfield.(PLUGINS, :name)
    else
        confirm_stack_nonempty() || return nothing
        used_plugins
    end
    for plugin in plugins
        if plugin in used_plugins
            printstyled(" • ", color=:blue)
        else
            printstyled(" ∘ ", color=:light_black)
        end
        println(plugin)
    end
end

const PLUGIN_SUBCOMMANDS = ReplCmd[
    ReplCmd{:plugin_add}(
        "add", "Add plugins to the first data collection",
        plugin_add),
    ReplCmd{:plugin_remove}(
        "remove", "Remove plugins from the first data collection",
        plugin_remove),
    ReplCmd{:plugin_edit}(
        "edit", "Edit the plugins used by the first data collection",
        plugin_edit),
    ReplCmd{:plugin_info}(
        "info", "Fetch the documentation of a plugin",
        DataToolkitBase.plugin_info),
    ReplCmd{:plugin_list}(
        "list", "List the plugins used by the first data collection

With '-a'/'--availible' all loaded plugins are listed instead.",
        plugin_list),
]

completions(::ReplCmd{:plugin_add}, sofar::AbstractString) =
    if !isempty(STACK)
        plugins = split(sofar, r", *| +")
        options = filter(p -> startswith(p, last(plugins)),
                         setdiff(getfield.(PLUGINS, :name),
                                 first(STACK).plugins,
                                 plugins))
        (Vector{String}(options),
         String(last(plugins)),
         !isempty(options))
    else
        String[]
    end

completions(::ReplCmd{:plugin_remove}, sofar::AbstractString) =
    if !isempty(STACK)
        plugins = split(sofar, r", *| +")
        options = setdiff(filter(p -> startswith(p, last(plugins)),
                                 first(STACK).plugins),
                          plugins)
        (Vector{String}(options),
         String(last(plugins)),
         !isempty(options))
    else
        String[]
    end

allcompletions(::ReplCmd{:plugin_info}) = getfield.(PLUGINS, :name)

allcompletions(::ReplCmd{:plugin_list}) = ["--availible"]
