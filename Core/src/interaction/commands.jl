# Utilities

function complete_collection(sofar::AbstractString)
    name_matches = filter(c -> startswith(c.name, sofar), STACK)
    if !isempty(name_matches)
        getproperty.(name_matches, :name)
    else
        uuid_matches = filter(c -> startswith(string(c.uuid), sofar), STACK)
        getproperty.(uuid_matches, :name)
    end |> Vector{String}
end

function complete_dataset(sofar::AbstractString)
    try # In case `resolve` or `getlayer` fail.
        relevant_options = if !isnothing(match(r"^.+::", sofar))
                identifier = Identifier(first(split(sofar, "::")))
                types = map(l -> l.type, resolve(identifier).loaders) |>
                    Iterators.flatten .|> string |> unique
                string.(string(identifier), "::", types)
        elseif !isnothing(match(r"^[^:]+:", sofar))
            layer, _ = split(sofar, ':', limit=2)
            filter(o -> startswith(o, sofar),
                   string.(layer, ':',
                           sort(unique(getproperty.(
                               getlayer(layer).datasets, :name)))))
        else
            filter(o -> startswith(o, sofar),
                   vcat(getproperty.(STACK, :name) .* ':',
                        getproperty.(getlayer(nothing).datasets, :name) |> unique))
        end
    catch _
        String[]
    end
end

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
            prompt(" Path to Data TOML file: ",
                   joinpath(if !isnothing(Base.active_project(false))
                                dirname(Base.active_project(false))
                            else pwd() end, "$name.toml"))
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
        println("Directory '$(dirname(path))' does not exist")
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
# Stack management
# ------------------

"""
    stack_list(::AbstractString; maxwidth::Int=displaysize(stdout)[2])
Print a table listing all of the current data collections on the stack.
"""
function stack_list(::AbstractString; maxwidth::Int=displaysize(stdout)[2])
    table_rows = displaytable(
        ["#", "Name", "Datasets", "Writable", "Plugins"],
        map(enumerate(STACK)) do (i, collection)
            [string(i), something(collection.name, ""),
             length(collection.datasets),
             ifelse(iswritable(collection), "yes", "no"),
             join(collection.plugins, ", ")]
        end; maxwidth)
    for row in table_rows
        print(stderr, ' ', row, '\n')
    end
end

"""
    stack_promote(input::AbstractString)
Parse and call the repl-format stack promotion command `input`.

`input` should consist of a data collection identifier and optionally a
promotion amount, either an integer or the character '*'.
"""
function stack_promote(input::AbstractString)
    ident, repeat = match(r"^(.*?)((?: *\d+| *\*)?)$", input).captures
    stack_move(@something(tryparse(Int, ident),
                          tryparse(UUID, ident),
                          String(ident)),
               -if strip(repeat) == "*"
                   length(STACK)
                else
                   something(tryparse(Int, repeat), 1)
                end)
    nothing
end

"""
    stack_demote(input::AbstractString)
Parse and call the repl-format stack demote command `input`.

`input` should consist of a data collection identifier and optionally a
promotion amount, either an integer or the character '*'.
"""
function stack_demote(input::AbstractString)
    ident, repeat = match(r"^(.*?)((?: \d+)?)$", input).captures
    stack_move(@something(tryparse(Int, ident),
                          tryparse(UUID, ident),
                          String(ident)),
               if strip(repeat) == "*"
                   length(STACK)
               else
                   something(tryparse(Int, repeat), 1)
               end)
    nothing
end

"""
    stack_load(input::AbstractString)
Parse and call the repl-format stack loader command `input`.

`input` should consist of a path to a Data TOML file or a folder containing a
Data.toml file. The path may be preceeded by a position in the stack to be
loaded to, either an integer or the character '*'.

`input` may also be the name of an existing data collection, in which case its
path is substituted.
"""
function stack_load(input::AbstractString)
    position, path = match(r"^((?:\d+ +)?)(.*)$", input).captures
    file = if !isempty(path)
        if !endswith(path, ".toml") && !isdir(path) &&
            !isnothing(findfirst(c -> c.name == path, STACK))
            getlayer(path).path
        else
            abspath(expanduser(path))
        end
    elseif Base.active_project(false) &&
        isfile(joinpath(Base.active_project(false), "Data.toml"))
        dirname(Base.active_project(false))
    elseif isfile("Data.toml")
        "Data.toml"
    else
        printstyled(" ! ", color=:yellow, bold=true)
        println("Provide a path to the Data TOML file to load")
        return nothing
    end
    if isdir(file)
        file = joinpath(file, "Data.toml")
    end
    if !isfile(file)
        printstyled(" ! ", color=:red, bold=true)
        println("File '$input' does not exist")
    else
        loadcollection!(file, index=something(tryparse(Int, position), 1))
    end
end

"""
    stack_remove(input::AbstractString)
Parse and call the repl-format stack removal command `input`.

`input` should consist of a data collection identifier.
"""
function stack_remove(input::AbstractString)
    if isempty(input)
        printstyled(" ! ", color=:yellow, bold=true)
        println("Identify the data collection that should be removed")
    else
        stack_remove!(@something(tryparse(Int, input),
                                 tryparse(UUID, input),
                                 String(input)))
        nothing
    end
end

const STACK_SUBCOMMANDS = ReplCmd[
    ReplCmd{:stack_list}(
        "", "List the data collections of the data stack", stack_list),
    ReplCmd{:stack_promote}(
        "promote", "Move an entry up the stack

An entry can be identified using any of the following:
- the current position in the stack
- the name of the data collection
- the UUID of the data collection

The number of positions the entry should be promoted by defaults to 1, but can
optionally be specified by putting either an integer or the character '*' after
the identifier. When '*' is given, the entry will be promoted to the top of the
data stack.

Examples with different identifier forms:
  promote 2
  promote mydata
  promote 853a9f6a-cd5e-4447-a0a4-b4b2793e0a48

Examples with different promotion degrees:
  promote mydata
  promote mydata 3
  promote mydata *", stack_promote),
    ReplCmd{:stack_demote}(
        "demote", "Move an entry down the stack

An entry can be identified using any of the following:
- the current position in the stack
- the name of the data collection
- the UUID of the data collection

The number of positions the entry should be demoted by defaults to 1, but can
optionally be specified by putting either an integer or the character '*' after
the identifier. When '*' is given, the entry will be demoted to the bottom of the
data stack.

Examples with different identifier forms:
  demote 2
  demote mydata
  demote 853a9f6a-cd5e-4447-a0a4-b4b2793e0a48

Examples with different demotion degrees:
  demote mydata
  demote mydata 3
  demote mydata *", stack_demote),
    ReplCmd{:stack_load}(
        "load", "Load a data collection onto the top of the stack

The data collection should be given by a path to either:
- a Data TOML file
- a folder containing a 'Data.toml' file

The path can be optionally preceeded by an position to insert the loaded
collection into the stack at. The default behaviour is to put the new collection
at the top of the stack.

Examples:
  load path/to/mydata.toml
  load 2 somefolder/", stack_load),
    ReplCmd{:stack_remove}(
        "remove", "Remove an entry from the stack

An entry can be identified using any of the following:
- the current position in the stack
- the name of the data collection
- the UUID of the data collection

Examples:
  remove 2
  remove mydata
  remove 853a9f6a-cd5e-4447-a0a4-b4b2793e0a48", stack_remove),
]

function completions(::ReplCmd{:stack_load}, sofar::AbstractString)
    pathsofar = first(match(r"^(?:\d+ *)?(.*)$", sofar).captures)
    currentsegment = reverse(first(split(reverse(pathsofar), '/', limit=2, keepempty=true)))
    nextsegments = getfield.(first(REPL.REPLCompletions.complete_path(pathsofar, 0)), :path)
    (if !isempty(nextsegments)
         nextsegments
     else String[] end,
     String(currentsegment),
     !isempty(nextsegments))
end

completions(::ReplCmd{:stack_promote}, sofar::AbstractString) =
    complete_collection(sofar)

completions(::ReplCmd{:stack_demote}, sofar::AbstractString) =
    complete_collection(sofar)

completions(::ReplCmd{:stack_remove}, sofar::AbstractString) =
    complete_collection(sofar)

push!(REPL_CMDS,
      ReplCmd(:stack,
              "Operate on the data collection stack",
              STACK_SUBCOMMANDS))

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

push!(REPL_CMDS,
      ReplCmd(:plugin,
              "Inspect and modify the set of plugins used

Call without any arguments to see the availible subcommands.",
              PLUGIN_SUBCOMMANDS))

# ------------------
# Configuration
# ------------------

"""
    config_segments(input::AbstractString)
Parse a string representation of a TOML-style dotted path into path segments,
and any remaining content.
"""
function config_segments(input::AbstractString)
    segments = String[]
    rest = '.' * input
    while !isempty(rest) && first(rest) == '.'
        seg, rest = peelword(rest[2:end], allowdot=false)
        !isempty(seg) && push!(segments, String(seg))
    end
    segments, strip(rest)
end

"""
    config_get(input::AbstractString)
Parse and call the repl-format config getter command `input`.
"""
function config_get(input::AbstractString)
    segments, rest = config_segments(input)
    if !isempty(rest)
        printstyled(" ! ", color=:yellow, bold=true)
        println("Trailing garbage ignored in get command: \"$rest\"")
    end
    value = config_get(segments)
    if value isa Dict && isempty(value)
        printstyled(" empty\n", color=:light_black)
    elseif value isa Dict
        TOML.print(value)
    else
        value
    end
end

"""
    config_set(input::AbstractString)
Parse and call the repl-format config setter command `input`.
"""
function config_set(input::AbstractString)
    segments, rest = config_segments(input)
    if isempty(rest)
        printstyled(" ! ", color=:red, bold=true)
        println("Value missing")
    else
        if isnothing(match(r"^true|false|[.\d]+|\".*\"|\[.*\]|\{.*\}$", rest))
            rest = string('"', rest, '"')
        end
        value = TOML.parse(string("value = ", rest))
        config_set!(segments, value["value"])
    end
end

"""
    config_unset(input::AbstractString)
Parse and call the repl-format config un-setter command `input`.
"""
function config_unset(input::AbstractString)
    segments, rest = config_segments(input)
    if !isempty(rest)
        printstyled(" ! ", color=:yellow, bold=true)
        println("Trailing garbage ignored in unset command: \"$rest\"")
    end
    config_unset!(segments)
end

const CONFIG_SUBCOMMANDS = ReplCmd[
    ReplCmd{:config_get}(
        "get", "Get the current configuration

The parameter to get the configuration of should be given using TOML-style dot
seperation.

Examples:
  get defaults.memorise
  get loadcache.path
  get my.\"special thing\".extra", config_get),
    ReplCmd{:config_set}(
        "set", "Set a configuration property

The parameter to set the configuration of should be given using TOML-style dot
seperation.

Similarly, the new value should be expressed using TOML syntax.

Examples:
  set defaults.memorise true
  set loadcache.path \"data/loadcache\"
  set my.\"special thing\".extra {a=1, b=2}", config_set),
    ReplCmd{:config_unset}(
        "unset", "Remove a configuration property

The parameter to be removed should be given using TOML-style dot seperation.

Examples:
  unset defaults.memorise
  unset loadcache.path
  unset my.\"special thing\".extra", config_unset),
]

push!(REPL_CMDS,
      ReplCmd(:config,
              "Inspect and modify the current configuration",
              CONFIG_SUBCOMMANDS))

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
            if isempty(collection.datasets)
                Vector{Any}[]
            else
                map(sort(collection.datasets, by = d -> d.name)) do dataset
                    [dataset.name,
                    first(split(get(dataset, "description", " "),
                                '\n', keepempty=false))]
                end
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

allcompletions(::ReplCmd{:list}) =
    filter(cn -> !isnothing(cn), map(c -> c.name, STACK))

# ------------------
# Show
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

completions(::ReplCmd{:show}, sofar::AbstractString) =
    complete_dataset(sofar)
