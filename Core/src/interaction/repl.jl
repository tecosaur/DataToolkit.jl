using REPL, REPL.LineEdit

# ------------------
# Setting up the 'data>' REPL and framework
# ------------------

"""
A command that can be used in the `data>` REPL (accessible through '$REPL_KEY').

A `ReplCmd` must have a:
- `name`, a symbol designating the command keyword.
- `trigger`, a string used as the command trigger (defaults to `String(name)`).
- `description`, a string giving a short overview of the functionality.
- `execute`, a function which will perform the command's action. The function
  must take a single argument, the rest of the command as an `AbstractString`
  (for example, 'cmd arg1 arg2' will call the execute function with "arg1 arg2").

# Constructors

```julia
ReplCmd{name::Symbol}(trigger::String, description::String, execute::Function)
ReplCmd{name::Symbol}(description::String, execute::Function)
ReplCmd(name::Union{Symbol, String}, trigger::String, description::String, execute::Function)
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
    trigger::String
    description::String
    execute::Function
end

ReplCmd{name}(description::String, execute::Function) where {name} =
    ReplCmd{name}(String(name), description, execute)

ReplCmd(name::Union{Symbol, String}, args...) =
    ReplCmd{Symbol(name)}(args...)

help(r::ReplCmd) = println(stderr, r.description)
completions(r::ReplCmd, sofar::AbstractString) =
    sort(filter(s -> startswith(s, sofar), allcompletions(r, sofar)))
allcompletions(::ReplCmd, ::AbstractString) = String[]

const REPL_CMDS = ReplCmd[]

function find_repl_cmd(cmd::AbstractString; warn::Bool=false,
                       commands::Vector{ReplCmd}=REPL_CMDS,
                       scope::String="Data REPL")
    replcmds = filter(c -> startswith(c.trigger, cmd), commands)
    if length(replcmds) == 1
        first(replcmds)
    elseif warn && length(replcmds) > 1
        printstyled(" ! ", color=:red, bold=true)
        println("Multiple matching REPL commands: ",
                join(getproperty.(replcmds, :trigger), ", "),
                ".")
    elseif warn # no matching commands
        printstyled(" ! ", color=:red, bold=true)
        println("The $scope command '$cmd' is not defined.")
    end
end

function execute_repl_cmd(line::AbstractString;
                          commands::Vector{ReplCmd}=REPL_CMDS,
                          scope::String="Data REPL")
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
    repl_cmd = find_repl_cmd(cmd; warn=true, commands, scope)
    if isnothing(repl_cmd)
        Expr(:block, :nothing)
    else
        repl_cmd.execute(rest)
    end
end

function toplevel_execute_repl_cmd(line::AbstractString)
    try
        execute_repl_cmd(line)
    catch e
        if e isa InterruptException
            printstyled(" !", color=:red, bold=true)
            print(" Aborted\n")
        else
            rethrow(e)
        end
    end
end

function complete_repl_cmd(line::AbstractString)
    if isempty(line)
        (sort(Vector{String}(
            map(c -> String(first(typeof(c).parameters)), REPL_CMDS))),
         "",
         true)
    else
        cmd_parts = split(line, limit = 2)
        cmd_name, rest = if length(cmd_parts) == 1
            cmd_parts[1], ""
        else
            cmd_parts
        end
        repl_cmd = find_repl_cmd(cmd_name)
        complete = if !isnothing(repl_cmd)
            completions(repl_cmd, rest)
        else
            Vector{String}(
                filter(ns -> startswith(ns, cmd_name),
                       sort(getproperty(REPL_CMDS, :trigger))))
        end
        if complete isa Tuple{Vector{String}, String, Bool}
            complete
        elseif complete isa Vector{String}
            (sort(complete),
                String(rest),
                !isempty(complete))
        else
            throw(error("REPL completions for $cmd_name returned strange result, $(typeof(complete))"))
        end
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
        () -> if isempty(STACK)
            "(⋅) data> "
        else
            "($(first(STACK).name)) data> "
        end;
        prompt_prefix,
        prompt_suffix,
        keymap_dict = LineEdit.default_keymap_dict,
        on_enter = LineEdit.default_enter_cb,
        complete = DataCompletionProvider(),
        sticky = true)
    data_mode.on_done = REPL.respond(toplevel_execute_repl_cmd, repl, data_mode)

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
# Interaction utilities
# ------------------

"""
    prompt(question::AbstractString, default::AbstractString="",
           allowempty::Bool=false, cleardefault::Bool=true)
Interactively ask `question` and return the response string, optionally
with a `default` value.

Unless `allowempty` is set an empty response is not accepted.
If `cleardefault` is set, then an initial backspace will clear the default value.

The prompt supports the following line-edit-y keys:
- left arrow
- right arrow
- home
- end
- delete forwards
- delete backwards

### Example

```julia-repl
julia> prompt("What colour is the sky? ")
What colour is the sky? Blue
"Blue"
```
"""
function prompt(question::AbstractString, default::AbstractString="",
                allowempty::Bool=false, cleardefault::Bool=true)
    printstyled(question, color=REPL_QUESTION_COLOR)
    get(stdout, :color, false) && print(Base.text_colors[REPL_USER_INPUT_COLOUR])
    REPL.Terminals.raw!(REPL.TerminalMenus.terminal, true)
    response = let response = collect(default)
        point = length(response)
        firstinput = true
        print("\e[s")
        while true
            print("\e[u\e[J")
            if String(response) == default
                print("\e[90m")
            end
            print(String(response))
            if point < length(response)
                print("\e[$(length(response) - point)D")
            end
            next = Char(REPL.TerminalMenus.readkey(REPL.TerminalMenus.terminal.in_stream))
            if next == '\r'  # RET
                if (!isempty(response) || allowempty)
                    print('\n')
                    break
                end
            elseif next == 'Ϭ' # DEL-forward
                if point < length(response)
                    deleteat!(response, point + 1)
                end
            elseif next == '\x03' # ^C
                print("\e[90m^C")
                throw(InterruptException())
            elseif next == '\x7f' # DEL
                if firstinput && cleardefault
                    response = Char[]
                    point = 0
                elseif point > 0
                    deleteat!(response, point)
                    point -= 1
                end
            elseif next == 'Ϩ' # <left>
                point = max(0, point - 1)
            elseif next == 'ϩ' # <right>
                point = min(length(response), point + 1)
            elseif next == 'ϭ' # HOME
                point = 0
            elseif next == 'Ϯ' # END
                point = length(response)
            else
                point += 1
                insert!(response, point, next)
            end
            firstinput = false
        end
        String(response)
    end
    REPL.Terminals.raw!(REPL.TerminalMenus.terminal, false)
    get(stdout, :color, false) && print("\e[m")
    response
end

"""
    prompt_char(question::AbstractString, options::Vector{Char},
                default::Union{Char, Nothing}=nothing)
Interatively ask `question`, only accepting `options` keys as answers.
All keys are converted to lower case on input. If `default` is not nothing and
'RET' is hit, then `default` will be returned.

Should '^C' be pressed, an InterruptException will be thrown.
"""
function prompt_char(question::AbstractString, options::Vector{Char},
                     default::Union{Char, Nothing}=nothing)
    printstyled(question, color=REPL_QUESTION_COLOR)
    REPL.Terminals.raw!(REPL.TerminalMenus.terminal, true)
    char = '\x01'
    while char ∉ options
        char = lowercase(Char(REPL.TerminalMenus.readkey(REPL.TerminalMenus.terminal.in_stream)))
        if char == '\r' && !isnothing(default)
            char = default
        elseif char == '\x03' # ^C
            print("\e[90m^C")
            throw(InterruptException())
        end
    end
    REPL.Terminals.raw!(REPL.TerminalMenus.terminal, false)
    get(stdout, :color, false) && print(Base.text_colors[REPL_USER_INPUT_COLOUR])
    print(stdout, char, '\n')
    get(stdout, :color, false) && print("\e[m")
    char
end

"""
    confirm_yn(question::AbstractString, default::Bool=false)
Interactively ask `question` and accept y/Y/n/N as the response.
If any other key is pressed, then `default` will be taken as the response.
A " [y/n]: " string will be appended to the question, with y/n capitalised
to indicate the default value.

### Example

```julia-repl
julia> confirm_yn("Do you like chocolate?", true)
Do you like chocolate? [Y/n]: y
true
```
"""
function confirm_yn(question::AbstractString, default::Bool=false)
    char = prompt_char(question * (" [y/N]: ", " [Y/n]: ")[1+ default],
                       ['y', 'n'], ('n', 'y')[1+default])
    char == 'y'
end

"""
    peelword(input::AbstractString)
Read the next 'word' from `input`. If `input` starts with a quote, this is the
unescaped text between the opening and closing quote. Other wise this is simply
the next word.

Returns a tuple of the form `(word, rest)`.

### Example

```julia-repl
julia> peelword("one two")
("one", "two")

julia> peelword("\"one two\" three")
("one two", "three")
```
"""
function peelword(input::AbstractString)
    if isempty(input)
        ("", "")
    elseif first(lstrip(input)) != '"' || count(==('"'), input) < 2
        Tuple(match(r"^\s*([^\s]+)\s*(.*?|)$", input).captures .|> String)
    else # Starts with " and at least two " in `input`.
        start = findfirst(!isspace, input)::Int
        stop = nextind(input, start)
        word = Char[]
        while input[stop] != '"' && stop <= lastindex(input)
            push!(word, input[stop + Int(input[stop] == '\\')])
            stop = nextind(input, stop, 1 + Int(input[stop] == '\\'))
        end
        (String(word), input[stop+1:end])
    end
end

# ------------------
# The help command
# ------------------

function help_cmd_table(; maxwidth::Int=displaysize(stdout)[2],
                        commands::Vector{ReplCmd}=REPL_CMDS)
    help_headings = ["Command", "Action"]
    help_lines = map(commands) do replcmd
        [String(first(typeof(replcmd).parameters)),
         first(split(replcmd.description, '\n'))]
    end
    map(displaytable(help_headings, help_lines; maxwidth)) do row
        print(stderr, ' ', row, '\n')
    end
end

function help_show(cmd::AbstractString; commands::Vector{ReplCmd}=REPL_CMDS)
    if isempty(cmd)
        help_cmd_table(; commands)
    else
        repl_cmd = find_repl_cmd(cmd; commands)
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
      ReplCmd(:help,
              "Display help information on the availible data commands.",
              help_show))

allcompletions(::ReplCmd{:help}, rest::AbstractString) =
    map(c -> String(first(typeof(c).parameters)), REPL_CMDS)
