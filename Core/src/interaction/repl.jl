using REPL, REPL.LineEdit

# ------------------
# Setting up the Data REPL and framework
# ------------------

@doc """
A command that can be used in the Data REPL (accessible through '$REPL_KEY').

A `ReplCmd` must have a:
- `name`, a symbol designating the command keyword.
- `trigger`, a string used as the command trigger (defaults to `String(name)`).
- `description`, a short overview of the functionality as a `string` or `display`able object.
- `execute`, either a list of sub-ReplCmds, or a function which will perform the
  command's action. The function must take a single argument, the rest of the
  command as an `AbstractString` (for example, 'cmd arg1 arg2' will call the
  execute function with "arg1 arg2").

# Constructors

```julia
ReplCmd{name::Symbol}(trigger::String, description::Any, execute::Function)
ReplCmd{name::Symbol}(description::Any, execute::Function)
ReplCmd(name::Union{Symbol, String}, trigger::String, description::Any, execute::Function)
ReplCmd(name::Union{Symbol, String}, description::Any, execute::Function)
```

# Examples

```julia
ReplCmd(:echo, "print the argument", identity)
ReplCmd(:addone, "return the input plus one", v -> 1 + parse(Int, v))
ReplCmd(:math, "A collection of basic integer arithmatic",
    [ReplCmd(:add, "a + b + ...", nums -> sum(parse.(Int, split(nums))))],
     ReplCmd(:mul, "a * b * ...", nums -> prod(parse.(Int, split(nums)))))
```

# Methods

```julia
help(::ReplCmd) # -> print detailed help
allcompletions(::ReplCmd) # -> list all candidates
completions(::ReplCmd, sofar::AbstractString) # -> list relevant candidates
```
""" ReplCmd

ReplCmd{name}(description::Any, execute::Union{Function, Vector{ReplCmd}}) where {name} =
    ReplCmd{name}(String(name), description, execute)

ReplCmd(name::Union{Symbol, String}, args...) =
    ReplCmd{Symbol(name)}(args...)

"""
    help(r::ReplCmd)

Print the help string for `r`.

    help(r::ReplCmd{<:Any, Vector{ReplCmd}})

Print the help string and subcommand table for `r`.
"""
function help(r::ReplCmd)
    if r.description isa AbstractString
        for line in eachsplit(rstrip(r.description), '\n')
            println("  ", line)
        end
    else
        display(r.description)
    end
end
function help(r::ReplCmd{<:Any, Vector{ReplCmd}})
    if r.description isa AbstractString
        for line in eachsplit(rstrip(r.description), '\n')
            println("  ", line)
        end
    else
        display(r.description)
    end
    print('\n')
    help_cmd_table(commands = r.execute, sub=true)
end

"""
    completions(r::ReplCmd, sofar::AbstractString)

Obtain a list of `String` completion candidates baesd on `sofar`.
All candidates should begin with `sofar`.

Should this function not be implemented for the specific ReplCmd `r`,
`allcompletions(r)` will be called and filter to candiadates that begin
with `sofar`.

If `r` has subcommands, then the subcommand prefix will be removed and
`completions` re-called on the relevant subcommand.
"""
completions(r::ReplCmd, sofar::AbstractString) =
    sort(filter(s -> startswith(s, sofar), allcompletions(r)))
completions(r::ReplCmd{<:Any, Vector{ReplCmd}}, sofar::AbstractString) =
    complete_repl_cmd(sofar, commands = r.execute)

"""
    allcompletions(r::ReplCmd)

Obtain all possible `String` completion candiadates for `r`.
This defaults to the empty vector `String[]`.

`allcompletions` is only called when `completions(r, sofar::AbstractString)` is
not implemented.
"""
allcompletions(::ReplCmd) = String[]

"""
The help-string for the help command itself.
This contains the template string \"<SCOPE>\", which
is replaced with the relevant scope at runtime.
"""
const HELP_CMD_HELP =
    """Display help information on the availible <SCOPE> commands

       For convenience, help information can also be accessed via '?', e.g. '?help'.

       Help for data transformers can also be accessed by asking for the help of the
       transformer name prefixed by ':' (i.e. ':transformer'), and a list of documented
       transformers can be pulled up with just ':'.

       Usage
       =====

       $REPL_PROMPT help
       $REPL_PROMPT help CMD
       $REPL_PROMPT help PARENT CMD
       $REPL_PROMPT PARENT help CMD
       $REPL_PROMPT help :
       $REPL_PROMPT help :TRANSFORMER
       """

"""
    find_repl_cmd(cmd::AbstractString; warn::Bool=false,
                  commands::Vector{ReplCmd}=REPL_CMDS,
                  scope::String="Data REPL")

Examine the command string `cmd`, and look for a command from `commands` that is
uniquely identified. Either the identified command or `nothing` will be returned.

Should `cmd` start with `help` or `?` then a `ReplCmd{:help}` command is returned.

If `cmd` is ambiguous and `warn` is true, then a message listing all potentially
matching commands is printed.

If `cmd` does not match any of `commands` and `warn` is true, then a warning
message is printed. Adittionally, should the named command in `cmd` have more
than a 3/5th longest common subsequence overlap with any of `commands`, then
those commands are printed as suggestions.
"""
function find_repl_cmd(cmd::AbstractString; warn::Bool=false,
                       commands::Vector{ReplCmd}=REPL_CMDS,
                       scope::String="Data REPL")
    replcmds = let candidates = filter(c -> startswith(c.trigger, cmd), commands)
        if isempty(candidates)
            candidates = filter(c -> issubseq(cmd, c.trigger), commands)
            if !isempty(candidates)
                char_filtered = filter(c -> startswith(c.trigger, first(cmd)), candidates)
                if !isempty(char_filtered)
                    candidates = char_filtered
                end
            end
        end
        candidates
    end
    all_cmd_names = getproperty.(commands, :trigger)
    if cmd == "" && "" in all_cmd_names
        replcmds[findfirst("" .== all_cmd_names)]
    elseif length(replcmds) == 0 && (cmd == "?" || startswith("help", cmd)) || length(cmd) == 0
        ReplCmd{:help}("help", replace(HELP_CMD_HELP, "<SCOPE>" => scope),
                       cmd -> help_show(cmd; commands))
    elseif length(replcmds) == 1
        first(replcmds)
    elseif length(replcmds) > 1 &&
        sum(cmd .== getproperty.(replcmds, :trigger)) == 1 # single exact match
        replcmds[findfirst(c -> c.trigger == cmd, replcmds)]
    elseif warn && length(replcmds) > 1
        printstyled(" ! ", color=:red, bold=true)
        print("Multiple matching $scope commands: ")
        candidates = filter(!=(""), getproperty.(replcmds, :trigger))
        for cand in candidates
            highlight_lcs(stdout, cand, String(cmd), before="\e[4m", after="\e[24m")
            cand === last(candidates) || print(", ")
        end
        print('\n')
    elseif warn # no matching commands
        printstyled(" ! ", color=:red, bold=true)
        println("The $scope command '$cmd' is not defined.")
        push!(all_cmd_names, "help")
        cmdsims = stringsimilarity.(cmd, all_cmd_names)
        if maximum(cmdsims, init=0) >= 0.5
            printstyled(" i ", color=:cyan, bold=true)
            println("Perhaps you meant '$(all_cmd_names[argmax(cmdsims)])'?")
        end
    end
end

"""
    execute_repl_cmd(line::AbstractString;
                     commands::Vector{ReplCmd}=REPL_CMDS,
                     scope::String="Data REPL")

Examine `line` and identify the leading command, then:
- Show an error if the command is not given in `commands`
- Show help, if help is asked for (see `help_show`)
- Call the command's execute function, if applicable
- Call `execute_repl_cmd` on the argument with `commands`
  set to the command's subcommands and `scope` set to the command's trigger,
  if applicable
"""
function execute_repl_cmd(line::AbstractString;
                          commands::Vector{ReplCmd}=REPL_CMDS,
                          scope::String="Data REPL")
    cmd_parts = split(line, limit = 2)
    cmd, rest = if length(cmd_parts) == 0
        "", ""
    elseif length(cmd_parts) == 1
        cmd_parts[1], ""
    else
        cmd_parts
    end
    if startswith(cmd, "?")
        execute_repl_cmd(string("help ", line[2:end]); commands, scope)
    elseif startswith("help", cmd) && !isempty(cmd) # help is special
        rest_parts = split(rest, limit=2)
        if length(rest_parts) == 1 && startswith(first(rest_parts), ':')
            help_show(Symbol(first(rest_parts)[2:end]))
        elseif length(rest_parts) <= 1
            help_show(rest; commands)
        elseif find_repl_cmd(rest_parts[1]; commands) isa ReplCmd{<:Any, Vector{ReplCmd}}
            execute_repl_cmd(string(rest_parts[1], " help ", rest_parts[2]);
                             commands, scope)
        else
            help_show(rest_parts[1]; commands)
        end
    else
        repl_cmd = find_repl_cmd(cmd; warn=true, commands, scope)
        if isnothing(repl_cmd)
        elseif repl_cmd isa ReplCmd{<:Any, Function}
            repl_cmd.execute(rest)
        elseif repl_cmd isa ReplCmd{<:Any, Vector{ReplCmd}}
            execute_repl_cmd(rest, commands = repl_cmd.execute, scope = repl_cmd.trigger)
        end
    end
end

"""
    toplevel_execute_repl_cmd(line::AbstractString)

Call `execute_repl_cmd(line)`, but gracefully catch an InterruptException if
thrown.

This is the main entrypoint for command execution.
"""
function toplevel_execute_repl_cmd(line::AbstractString)
    try
        execute_repl_cmd(line)
    catch e
        if e isa InterruptException
            printstyled(" !", color=:red, bold=true)
            print(" Aborted\n")
        else
            rethrow()
        end
    end
end

"""
    complete_repl_cmd(line::AbstractString; commands::Vector{ReplCmd}=REPL_CMDS)

Return potential completion candidates for `line` provided by `commands`.
More specifically, the command being completed is identified and
`completions(cmd::ReplCmd{:cmd}, sofar::AbstractString)` called.

Special behaviour is implemented for the help command.
"""
function complete_repl_cmd(line::AbstractString; commands::Vector{ReplCmd}=REPL_CMDS)
    if isempty(line)
        (sort(vcat(getfield.(commands, :trigger), "help")),
         "",
         true)
    else
        cmd_parts = split(line, limit = 2)
        cmd_name, rest = if length(cmd_parts) == 1
            cmd_parts[1], ""
        else
            cmd_parts
        end
        repl_cmd = find_repl_cmd(cmd_name; commands)
        complete = if !isnothing(repl_cmd) && line != cmd_name
            if repl_cmd isa ReplCmd{:help}
                # This can't be a `completions(...)` call because we
                # need to access `commands`.
                if startswith(rest, ':') # transformer help
                    filter(t -> startswith(t, rest),
                           string.(':', TRANSFORMER_DOCUMENTATION .|>
                               first .|> last |> unique))
                else # command help
                    Vector{String}(filter(ns -> startswith(ns, rest),
                                          getfield.(commands, :trigger)))
                end
            else
                completions(repl_cmd, rest)
            end
        else
            all_cmd_names = vcat(getfield.(commands, :trigger), "help")
            # Keep any ?-prefix if getting help, otherwise it would be nice
            # to end with a space to get straight to the sub-command/argument.
            all_cmd_names = if startswith(cmd_name, "?")
               '?' .* all_cmd_names
            else
               all_cmd_names .* ' '
            end
            cmds = filter(ns -> startswith(ns, cmd_name), all_cmd_names)
            (sort(cmds),
             String(line),
             !isempty(cmds))
        end
        if complete isa Tuple{Vector{String}, String, Bool}
            complete
        elseif complete isa Vector{String}
            (sort(complete),
             String(rest),
             !isempty(complete))
        else
            error("REPL completions for $cmd_name returned strange result, $(typeof(complete))")
        end
    end
end

"""
A singleton to allow for for Data REPL specific completion dispatching.
"""
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

"""
    init_repl()

Construct the Data REPL `LineEdit.Prompt` and configure it and the REPL to
behave appropriately. Other than boilerplate, this basically consists of:
- Setting the prompt style
- Setting the execution function (`toplevel_execute_repl_cmd`)
- Setting the completion to use `DataCompletionProvider`
"""
function init_repl()
    # With *heavy* inspiration from https://github.com/MasonProtter/ReplMaker.jl
    repl = Base.active_repl
    if !isdefined(repl, :interface)
        repl.interface = REPL.setup_interface(repl)
    end
    julia_mode = repl.interface.modes[1]
    prompt_prefix, prompt_suffix = if repl.hascolor
        REPL_PROMPTSTYLE, "\e[m"
    else
        "", ""
    end

    data_mode = LineEdit.Prompt(
        () -> if isempty(STACK)
            "(⋅) $REPL_PROMPT "
        else
            "($(first(STACK).name)) $REPL_PROMPT "
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
           allowempty::Bool=false, cleardefault::Bool=true,
           multiline::Bool=false)

Interactively ask `question` and return the response string, optionally
with a `default` value. If `multiline` is true, `RET` must be pressed
twice consecutively to submit a value.

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
function prompt(question::AbstractString, default::AbstractString="";
                 allowempty::Bool=false, cleardefault::Bool=true,
                 multiline::Bool=false)
    firstinput = true
    # Set `:color` to `false` in the stdout, so that the
    # terminal doesn't report color support, and the
    # prompt isn't bold.
    term = REPL.Terminals.TTYTerminal(
        get(ENV, "TERM", Sys.iswindows() ? "" : "dumb"),
        stdin, IOContext(stdout, :color => false), stderr)
    keymap = REPL.LineEdit.keymap([
        Dict{Any, Any}(
            "^C" => (_...) -> throw(InterruptException()),
            # Backspace
            '\b' => function (s::REPL.LineEdit.MIState, o...)
                if firstinput && cleardefault
                    REPL.LineEdit.edit_clear(s)
                else
                    REPL.LineEdit.edit_backspace(s)
                end
            end,
            # Delete
            "\e[3~" => function (s::REPL.LineEdit.MIState, o...)
                if firstinput && cleardefault
                    REPL.LineEdit.edit_clear(s)
                else
                    REPL.LineEdit.edit_delete(s)
                end
            end,
            # Return
            '\r' => function (s::REPL.LineEdit.MIState, o...)
                if multiline
                    if eof(REPL.LineEdit.buffer(s)) && s.key_repeats >= 1
                        REPL.LineEdit.commit_line(s)
                        :done
                    else
                        REPL.LineEdit.edit_insert_newline(s)
                    end
                else
                    if REPL.LineEdit.on_enter(s) &&
                        (allowempty || REPL.LineEdit.buffer(s).size != 0)
                        REPL.LineEdit.commit_line(s)
                        :done
                    else
                        REPL.LineEdit.beep(s)
                    end
                end
            end),
        REPL.LineEdit.default_keymap,
        REPL.LineEdit.escape_defaults
    ])
    prompt = REPL.LineEdit.Prompt(
        question;
        prompt_prefix = Base.text_colors[REPL_QUESTION_COLOR],
        prompt_suffix = Base.text_colors[ifelse(
            isempty(default), REPL_USER_INPUT_COLOUR, :light_black)],
        keymap_dict = keymap,
        complete = REPL.LatexCompletions(),
        on_enter = _ -> true)
    interface = REPL.LineEdit.ModalInterface([prompt])
    istate = REPL.LineEdit.init_state(term, interface)
    pstate = istate.mode_state[prompt]
    if !isempty(default)
        write(pstate.input_buffer, default)
    end
    Base.reseteof(term)
    REPL.LineEdit.raw!(term, true)
    REPL.LineEdit.enable_bracketed_paste(term)
    try
        pstate.ias = REPL.LineEdit.InputAreaState(0, 0)
        REPL.LineEdit.refresh_multi_line(term, pstate)
        while true
            kmap = REPL.LineEdit.keymap(pstate, prompt)
            matchfn = REPL.LineEdit.match_input(kmap, istate)
            kdata = REPL.LineEdit.keymap_data(pstate, prompt)
            status = matchfn(istate, kdata)
            if status === :ok
            elseif status === :ignore
                istate.last_action = istate.current_action
            elseif status === :done
                print("\e[F")
                if firstinput
                    pstate.p.prompt_suffix = Base.text_colors[REPL_USER_INPUT_COLOUR]
                    REPL.LineEdit.refresh_multi_line(term, pstate)
                end
                print("\e[39m\n")
                return String(rstrip(REPL.LineEdit.input_string(pstate), '\n'))
            else
                return nothing
            end
            if firstinput
                pstate.p.prompt_suffix = Base.text_colors[REPL_USER_INPUT_COLOUR]
                REPL.LineEdit.refresh_multi_line(term, pstate)
                firstinput = false
            end
        end
    finally
        REPL.LineEdit.raw!(term, false) &&
            REPL.LineEdit.disable_bracketed_paste(term)
    end
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
            print("\e[m^C\n")
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
function peelword(input::AbstractString; allowdot::Bool=true)
    if isempty(input)
        ("", "")
    elseif first(lstrip(input)) != '"' || count(==('"'), input) < 2
        Tuple(match(ifelse(allowdot,
                           r"^\s*([^\s][^\s]*)\s*(.*?|)$",
                           r"^\s*([^\s][^\s.]*)\s*(.*?|)$"),
                    input).captures .|> String)
    else # Starts with " and at least two " in `input`.
        start = findfirst(!isspace, input)::Int
        stop = nextind(input, start)
        maxstop = lastindex(input)
        word = Char[]
        while input[stop] != '"' && stop <= maxstop
            push!(word, input[stop + Int(input[stop] == '\\')])
            stop = nextind(input, stop, 1 + Int(input[stop] == '\\'))
        end
        stop = nextind(input, stop)
        if stop <= maxstop && isspace(input[stop])
            stop = nextind(input, stop)
        end
        (String(word), input[stop:end])
    end
end

# ------------------
# The help command
# ------------------

"""
    help_cmd_table(; maxwidth::Int=displaysize(stdout)[2],
                   commands::Vector{ReplCmd}=REPL_CMDS,
                   sub::Bool=false)

Print a table showing the triggers and descriptions (limited to the first line)
of `commands`, under the headers "Command" and "Action" (or "Subcommand" if
`sub` is set). The table is truncated if necessary so it is no wider than
`maxwidth`.
"""
function help_cmd_table(; maxwidth::Int=displaysize(stdout)[2]-2,
                        commands::Vector{ReplCmd}=REPL_CMDS,
                        sub::Bool=false)
    help_headings = [if sub "Subcommand" else "Command" end, "Action"]
    help_lines = map(commands) do replcmd
        String[replcmd.trigger,
               first(split(string(replcmd.description), '\n'))]
    end
    push!(help_lines, ["help", "Display help text for commands and transformers"])
    map(displaytable(help_headings, help_lines; maxwidth)) do row
        print(stderr, "  ", row, '\n')
    end
end

"""
    help_show(cmd::AbstractString; commands::Vector{ReplCmd}=REPL_CMDS)

If `cmd` refers to a command in `commands`, show its help (via `help`).
If `cmd` is empty, list `commands` via `help_cmd_table`.
"""
function help_show(cmd::AbstractString; commands::Vector{ReplCmd}=REPL_CMDS)
    if all(isspace, cmd)
        help_cmd_table(; commands)
        println("\n  \e[2;3mCommands can also be triggered by unique prefixes or substrings.\e[22;23m")
    else
        repl_cmd = find_repl_cmd(strip(cmd); commands, warn=true)
        if !isnothing(repl_cmd)
            help(repl_cmd)
        end
    end
    nothing
end

"""
    transformer_docs(name::Symbol, type::Symbol=:any)

Retur the documentation for the transformer identified by `name`,
or `nothing` if no documentation entry could be found.
"""
function transformer_docs(name::Symbol, type::Symbol=:any)
    tindex = findfirst(
        t -> first(t)[2] === name && (type === :any || first(t)[1] === type),
        TRANSFORMER_DOCUMENTATION)
    if !isnothing(tindex)
        last(TRANSFORMER_DOCUMENTATION[tindex])
    end
end

"""
    transformers_printall()

Print a list of all documented data transformers, by category.
"""
function transformers_printall()
    docs = (storage = Pair{Symbol, Any}[],
            loader = Pair{Symbol, Any}[],
            writer = Pair{Symbol, Any}[])
    for ((type, name), doc) in TRANSFORMER_DOCUMENTATION
        if type ∈ (:storage, :loader, :writer)
            push!(getfield(docs, type), name => doc)
        else
            @warn "Documentation entry for $name gives invalid transformer type $type (should be 'storage', 'loader', or 'writer')"
        end
    end
    sort!.(values(docs), by = first)
    for type in (:storage, :loader, :writer)
        entries = getfield(docs, type)
        printstyled(" $type transformers ($(length(entries)))\n",
                    color=:blue, bold=true)
        for (name, doc) in entries
            printstyled("   • ", color=:blue)
            println(name)
        end
        type === :writer || print('\n')
    end
end

"""
    help_show(transformer::Symbol)

Show documentation of a particular data `transformer` (should it exist).

In the special case that `transformer` is `Symbol("")`, a list of all documented
transformers is printed.
"""
function help_show(transformer::Symbol)
    if transformer === Symbol("") # List all documented transformers
        transformers_printall()
    else
        tdocs = transformer_docs(transformer)
        if isnothing(tdocs)
            printstyled(" ! ", color=:red, bold=true)
            println("There is no documentation for the '$transformer' transformer")
        else
            display(tdocs)
        end
    end
end
