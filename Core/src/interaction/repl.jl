using REPL, REPL.LineEdit

const REPL_KEY = '}'
const REPL_NAME = :DataRepl
const REPL_PROMPTSTYLE = Base.text_colors[:magenta]

"""
A command that can be used in the `data>` REPL (accessible through '$REPL_KEY').

A `ReplCmd` must have a:
- `name`, a symbol designating the command keyword.
- `description`, a string giving a short overview of the functionality.
- `execute`, a function which will perform the command's action. The function
  must take a single argument, the rest of the command as an `AbstractString`
  (for example, 'cmd arg1 arg2' will call the execute function with "arg1 arg2").

A `ReplCmd` may also (optionally) have a `shorthand` which triggers the command.

# Constructors

```julia
ReplCmd{name::Symbol}(shorthand::Union{String, Nothing}, description::String, execute::Function)
ReplCmd{name::Symbol}(description::String, execute::Function)
ReplCmd(name::Union{Symbol, String}, shorthand::Union{String, Nothing}, description::String, execute::Function)
ReplCmd(name::Union{Symbol, String}, description::String, execute::Function)
```

# Methods

```julia
help(::ReplCmd) # -> print detailed help
allcompletions(::ReplCmd, sofar::AbstractString) # -> list all candidates
completions(::ReplCmd, sofar::AbstractString) # -> list relevant candidates
```
"""
struct ReplCmd{name}
    shorthand::Union{String, Nothing}
    description::String
    execute::Function
end

ReplCmd{name}(description::String, execute::Function) where {name} =
    ReplCmd{name}(nothing, description, execute)

ReplCmd(name::Union{Symbol, String}, args...) =
    ReplCmd{Symbol(name)}(args...)

help(r::ReplCmd) = println(stderr, r.description)
completions(r::ReplCmd, sofar::AbstractString) =
    filter(s -> startswith(s, sofar), allcompletions(r, sofar))
allcompletions(::ReplCmd, ::AbstractString) = String[]

const REPL_CMDS = ReplCmd[]

function find_repl_cmd(cmd::AbstractString)
    replcmds =
        filter(c -> String(first(typeof(c).parameters)) == cmd || c.shorthand == cmd,
               REPL_CMDS)
    if length(replcmds) > 0
        first(replcmds)
    end
end

function execute_repl_cmd(line::AbstractString)
    cmd_parts = split(line, limit = 2)
    cmd, rest = if length(cmd_parts) == 1
        cmd_parts[1], ""
    else
        cmd_parts
    end
    if startswith(cmd, "?") # help is special
        rest = cmd[2:end] * rest
        cmd = "help"
    end
    repl_cmd = find_repl_cmd(cmd)
    if isnothing(repl_cmd)
        @error "The Data REPL command '$cmd' is not defined."
        Expr(:block, :nothing)
    else
        repl_cmd.execute(rest)
    end
end

function complete_repl_cmd(line::AbstractString)
    complete = if isempty(line)
        Vector{String}(
            map(c -> String(first(typeof(c).parameters)), REPL_CMDS))
    else
        cmd_parts = split(line, limit = 2)
        cmd_name, rest = if length(cmd_parts) == 1
            cmd_parts[1], ""
        else
            cmd_parts
        end
        repl_cmd = find_repl_cmd(cmd_name)
        if !isnothing(repl_cmd)
            completions(repl_cmd, rest)
        else
            nameandshortcut = vcat(
                map(c -> String(first(typeof(c).parameters)), REPL_CMDS),
                filter(!isnothing, map(c -> c.shorthand, REPL_CMDS)))
            Vector{String}(
                filter(ns -> startswith(ns, cmd_name), sort(nameandshortcut)))
        end
    end
    if complete isa Tuple{Vector{String}, String, Bool}
        complete
    elseif complete isa Vector{String}
        (sort(complete),
         String(first(split(line, limit=2, keepempty=true))),
         !isempty(complete))
    else
        throw(error("REPL completions for $cmd_name returned strange result, $(typeof(complete))"))
    end
end

struct DataCompletionProvider <: REPL.LineEdit.CompletionProvider end

function REPL.complete_line(::DataCompletionProvider,
                            state::REPL.LineEdit.PromptState)
    # See REPL.jl complete_line(c::REPLCompletionProvider, s::PromptState)
    partial = REPL.beforecursor(state.input_buffer)
    full = REPL.LineEdit.input_string(state)
    if partial != full
        # For now, only complete at end of line
        return ([], "", false)
    end
    complete_repl_cmd(full)
end

function init_repl()
    # With *heavy* inspiration taken from https://github.com/MasonProtter/ReplMaker.jl
    repl = Base.active_repl
    if !isdefined(repl, :interface)
        repl.interface = repl.setup_interface(repl)
    end
    julia_mode = repl.interface.modes[1]
    prompt_prefix, prompt_suffix = if repl.hascolor
        REPL_PROMPTSTYLE, "\e[m"
    else
        "", ""
    end

    data_mode = LineEdit.Prompt(
        "data> ";
        prompt_prefix,
        prompt_suffix,
        keymap_dict = LineEdit.default_keymap_dict,
        on_enter = LineEdit.default_enter_cb,
        complete = DataCompletionProvider(),
        sticky = true)
    data_mode.on_done = REPL.respond(execute_repl_cmd, repl, data_mode)

    push!(repl.interface.modes, data_mode)

    history_provider = julia_mode.hist
    history_provider.mode_mapping[REPL_NAME] = data_mode
    data_mode.hist = history_provider

    _, search_keymap = LineEdit.setup_search_keymap(history_provider)
    _, prefix_keymap = LineEdit.setup_prefix_keymap(history_provider, data_mode)
    julia_keymap = REPL.mode_keymap(julia_mode)

    data_mode.keymap_dict = LineEdit.keymap(Dict{Any, Any}[
        search_keymap,
        julia_keymap,
        prefix_keymap,
        LineEdit.history_keymap,
        LineEdit.default_keymap,
        LineEdit.escape_defaults
    ])

    key_alt_action =
        something(deepcopy(get(julia_mode.keymap_dict, REPL_KEY, nothing)),
                  (state, args...) -> LineEdit.edit_insert(state, REPL_KEY))
    function key_action(state, args...)
                if isempty(state) || position(LineEdit.buffer(state)) == 0
            function transition_action()
                LineEdit.state(state, data_mode).input_buffer =
                    copy(LineEdit.buffer(state))
            end
            LineEdit.transition(transition_action, state, data_mode)
        else
            key_alt_action(state, args...)
        end
    end

    data_keymap = Dict{Any, Any}(REPL_KEY => key_action)
    julia_mode.keymap_dict =
        LineEdit.keymap_merge(julia_mode.keymap_dict, data_keymap)

    data_mode
end

# ------------------
# REPL Commands
# ------------------

# help

function help_cmd_table()
    help_headings = ["Command", "Shorthand", "Action"]
    help_lines = map(REPL_CMDS) do replcmd
        [String(first(typeof(replcmd).parameters)),
         something(replcmd.shorthand, ""),
         replcmd.description]
    end
    map(displaytable(help_headings, help_lines)) do row
        print(stderr, ' ', row, '\n')
    end
end

function help_show(cmd::AbstractString)
    if isempty(cmd)
        help_cmd_table()
    else
        repl_cmd = DataToolkitBase.find_repl_cmd(cmd)
        if !isnothing(repl_cmd)
            help(repl_cmd)
        else
            printstyled(stderr, "ERROR: ", bold=true, color=:red)
            println(stderr, "Data command $cmd is not defined")
        end
    end
    Expr(:block, :nothing)
end

push!(REPL_CMDS,
      ReplCmd(:help, "?",
              "Display help information on the availible data commands.",
              help_show))

allcompletions(::ReplCmd{:help}, rest::AbstractString) =
    map(c -> String(first(typeof(c).parameters)), REPL_CMDS)

# list

function list_datasets(collection_str::AbstractString)
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
            map(collection.datasets) do dataset
                [dataset.name, get(dataset, "description", "")]
            end)
        for row in table_rows
            print(stderr, ' ', row, '\n')
        end
    end
end

push!(REPL_CMDS,
      ReplCmd(:list, "l",
              "List the datasets in a certain collection.",
              list_datasets))

allcompletions(::ReplCmd{:list}, rest::AbstractString) =
    filter(cn -> !isnothing(cn), map(c -> c.name, STACK))

help(r::ReplCmd{:list}) = println(stderr,
    r.description, "\n",
    "By default, the datasets of the active collection are shown."
)

# stack

function stack_table(::String)
    table_rows = displaytable(
        ["#", "Name", "Datasets", "Plugins"],
        map(enumerate(STACK)) do (i, collection)
            [string(i), something(collection.name, ""),
            length(collection.datasets), join(collection.plugins, ", ")]
        end)
    for row in table_rows
        print(stderr, ' ', row, '\n')
    end
end

push!(REPL_CMDS,
      ReplCmd(:stack,
              "List the data collections in the stack.",
              stack_table))

# show

push!(REPL_CMDS,
    ReplCmd(:show,
        "List the dataset refered to by an identifier.",
        ds -> if isempty(ds)
            println(stderr, "Provide a dataset to be shown.")
        else
            dataset(ds)
        end))

# get

push!(REPL_CMDS,
      ReplCmd(:get,
              "Fetch data from a certain location.",
              identity))
