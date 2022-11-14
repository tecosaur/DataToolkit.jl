# ------------------
# Initialisation
# ------------------

"""
    init(input::AbstractString)
Parse and call the repl-format init command `input`.
If required information is missing, the user will be interactively questioned.

`input` should be of the following form:

```
[NAME] [[at] PATH] [with [-n] [PLUGINS...]]
```
"""
function init(input::AbstractString)
    rest = input

    name = if isempty(rest)
        missing
    elseif first(peelword(rest)) == "at"
        _, rest = peelword(rest)
        missing
    else
        word, _ = peelword(rest)
        if endswith(word, ".toml") ||
            ispath(expanduser(word)) ||
            (occursin('/', word) && isdir(dirname(expanduser(word))))
            missing
        else
            _, rest = peelword(rest) # remove $word
            if first(peelword(rest)) == "at"
                _, rest = peelword(rest) # remove "at"
            end
            word
        end
    end

    path = if isempty(rest)
        if !isnothing(Base.active_project(false)) &&
            !isfile(joinpath(dirname(Base.active_project(false)), "Data.toml")) &&
            confirm_yn(" Create Data.toml for current project?", true)
            dirname(Base.active_project(false))
        else
            prompt(" Path to Data TOML file: ")
        end
    elseif first(peelword(rest)) != "with"
        path, rest = peelword(rest)
        path
    end |> expanduser |> abspath

    if !endswith(path, ".toml")
        path = joinpath(path, "Data.toml")
    end

    while !isdir(dirname(path))
        printstyled(" ! ", color=:yellow, bold=true)
        println("Directory 'dirname($path)' does not exist")
        createp = confirm_yn(" Would you like to create this directory?", true)
        if createp
            mkpath(dirname(path))
        else
            path = prompt(" Path to Data TOML file: ") |> expanduser |> abspath
            if !endswith(path, ".toml")
                path = joinpath(path, "Data.toml")
            end
        end
    end

    if isfile(path)
        printstyled(" ! ", color=:yellow, bold=true)
        println("File '$path' already exists")
        overwritep = confirm_yn(" Overwrite this file?", false)
        if !overwritep
            return nothing
        end
    end

    if ismissing(name)
        name = if basename(path) == "Data.toml"
            path |> dirname |> basename
        else
            first(splitext(basename(path)))
        end
        name = prompt(" Name: ", name)
    end

    init(name, path)
    nothing
end

push!(REPL_CMDS,
    ReplCmd(:init,
        "Initialise a new data collection

Optionally, a data collection name and path can be specified with the forms:
  init [NAME]
  init [PATH]
  init [NAME] [PATH]
  init [NAME] at [PATH]

Plugins can also be specified by adding a \"with\" argument,
  init [...] with PLUGINS...
To omit the default set of plugins, put \"with -n\" instead, i.e.
  init [...] with -n PLUGINS...

Example usages:
  init
  init /tmp/test
  init test at /tmp/test
  init test at /tmp/test with plugin1 plugin2",
        init))

# ------------------
# Plugins
# ------------------

"""
    confirm_stack_nonempty(; quiet::Bool=false)
Return `true` if STACK is non-empty.

Unless `quiet` is set, should the stack be empty a warning message is emmited.
"""
confirm_stack_nonempty(; quiet::Bool=false) =
    !isempty(STACK) || begin
        if !quiet
            printstyled(" ! ", color=:red, bold=true)
            println("The data collection stack is empty")
        end
        false
    end

"""
    confirm_stack_first_writable(; quiet::Bool=false)
First call `confirm_stack_nonempty` then return `true` if the first collection
of STACK is writable.

Unless `quiet` is set, should this not be the case a warning message is emmited.
"""
confirm_stack_first_writable(; quiet::Bool=false) =
    confirm_stack_nonempty(; quiet) &&
    (iswritable(first(STACK)) || begin
        if !quiet
            printstyled(" ! ", color=:red, bold=true)
            println("The first item on the data collection stack is not writable")
        end
        false
    end)

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
    plugin_add(plugins)
end

"""
    plugin_remove(input::AbstractString)
Parse and call the repl-format plugin removal command `input`.

`input` should consist of a list of plugin names.
"""
function plugin_remove(input::AbstractString)
    confirm_stack_first_writable() || return nothing
    plugins = split(input, r", *| +")
    notpresent = setdiff(plugins, first(STACK).plugins)
    if !isempty(notpresent)
        printstyled(" ! ", color=:yellow)
        println("The plugins $(join(notpresent, ", ", ", and ")) were not used to begin with")
    end
    plugin_remove(plugins)
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
    deleteat!(first(STACK).plugins, indexin(removed_plugins, original_plugins))
    append!(first(STACK).plugins, added_plugins)
    write(first(STACK))
    if isempty(added_plugins) && isempty(removed_plugins)
        printstyled(" ✓ No change to plugins\n", color=:green)
    else
        isempty(added_plugins) ||
            printstyled(" ✓ Added plugins: $(join(''' .* added_plugins .* ''', ", "))\n", color=:green)
        isempty(removed_plugins) ||
            printstyled(" ✓ Removed plugins: $(join(''' .* removed_plugins .* ''', ", "))\n", color=:green)
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
        printstyled(" • ", color=ifelse(plugin in used_plugins, :blue, :light_black))
        println(plugin)
    end
end

const PLUGIN_SUBCOMMANDS = ReplCmd[
    ReplCmd{:plugin_add}(
        "add", "Add plugins to the first data collection", plugin_add),
    ReplCmd{:plugin_remove}(
        "remove", "Remove plugins from the first data collection", plugin_remove),
    ReplCmd{:plugin_edit}(
        "edit", "Edit the plugins used by the first data collection", plugin_edit),
    ReplCmd{:plugin_info}(
        "info", "Fetch the documentation of a plugin", plugin_info),
    ReplCmd{:plugin_list}(
        "list", "List the plugins used by the first data collection

With '-a'/'--availible' all loaded plugins are listed instead.", plugin_list),
]

allcompletions(::ReplCmd{:plugin_add}) =
    if !isempty(STACK)
        setdiff(getfield.(PLUGINS, :name), first(STACK).plugins)
    else
        String[]
    end

allcompletions(::ReplCmd{:plugin_remove}) =
    if !isempty(STACK)
        first(STACK).plugins
    else
        String[]
    end

allcompletions(::ReplCmd{:plugin_info}) = getfield.(PLUGINS, :name)

allcompletions(::ReplCmd{:plugin_list}) = ["-a", "--availible"]

push!(REPL_CMDS,
      ReplCmd(:plugin,
              "Inspect and modify the set of plugins used

Call without any arguments to see the availible subcommands.",
              PLUGIN_SUBCOMMANDS))

# ------------------
# List datasets
# ------------------

function list_datasets(collection_str::AbstractString; maxwidth::Int=displaysize(stdout)[2])
    if isempty(STACK)
        println(stderr, "The data collection stack is empty.")
    else
        collection = if isempty(collection_str)
            getlayer(nothing)
        else
            getlayer(collection_str)
        end
        table_rows = displaytable(
            ["Dataset", "Description"],
            map(sort(collection.datasets, by = d -> d.name)) do dataset
                [dataset.name,
                 first(split(get(dataset, "description", " "),
                             '\n', keepempty=false))]
            end; maxwidth)
        for row in table_rows
            print(stderr, ' ', row, '\n')
        end
    end
end

push!(REPL_CMDS,
      ReplCmd(:list,
              "List the datasets in a certain collection

By default, the datasets of the active collection are shown.",
              list_datasets))

allcompletions(::ReplCmd{:list}, rest::AbstractString) =
    filter(cn -> !isnothing(cn), map(c -> c.name, STACK))

# ------------------
# Stack
# ------------------

function stack_table(::String; maxwidth::Int=displaysize(stdout)[2])
    table_rows = displaytable(
        ["#", "Name", "Datasets", "Plugins"],
        map(enumerate(STACK)) do (i, collection)
            [string(i), something(collection.name, ""),
            length(collection.datasets), join(collection.plugins, ", ")]
        end; maxwidth)
    for row in table_rows
        print(stderr, ' ', row, '\n')
    end
end

push!(REPL_CMDS,
      ReplCmd(:stack,
              "List the data collections in the stack.",
              stack_table))

# ------------------
# Stack
# ------------------

push!(REPL_CMDS,
    ReplCmd(:show,
        "List the dataset refered to by an identifier.",
        ident -> if isempty(ident)
            println("Provide a dataset to be shown.")
        else
            ds = resolve(parse(Identifier, ident))
            display(ds)
            if ds isa DataSet
                print("  UUID:    ")
                printstyled(ds.uuid, '\n', color=:light_magenta)
                if !isnothing(get(ds, "description"))
                    indented_desclines =
                        join(split(strip(get(ds, "description")),
                                   '\n'), "\n   ")
                    println("\n  “\e[3m", indented_desclines, "\e[m”")
                end
            end
            nothing
        end))

function allcompletions(::ReplCmd{:show}, sofar::AbstractString)
    try # In case `resolve` or `getlayer` fail.
        if !isnothing(match(r"^.+::", sofar))
                identifier = Identifier(first(split(sofar, "::")))
                types = map(l -> l.type, resolve(identifier).loaders) |>
                    Iterators.flatten .|> string |> unique
                string.(string(identifier), "::", types)
        elseif !isnothing(match(r"^[^:]+:", sofar))
            layer, _ = split(sofar, ':', limit=2)
            string.(layer, ':',
                    getproperty.(getlayer(layer).datasets, :name) |> unique)
        else
            vcat(getproperty.(STACK, :name) .* ':',
                getproperty.(getlayer(nothing).datasets, :name) |> unique)
        end
    catch _
        String[]
    end
end
