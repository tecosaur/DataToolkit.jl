# Initialisation and running of the `data>` REPL mode.

"""
    execute_repl_cmd(line::AbstractString;
                     commands::Vector{ReplCmd}=REPL_CMDS,
                     scope::String="Data REPL")

Examine `line` and identify the leading command, then:
- Show an error if the command is not given in `commands`
- Show help, if help is asked for (see `help_show`)
- Call the command's execute function, if applicable
- Call `execute_repl_cmd` on the argument with `commands`
  set to the command's subcommands and `scope` set to the command's name,
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
        elseif find_repl_cmd(rest_parts[1]; commands) isa ReplCmd{Vector{ReplCmd}}
            execute_repl_cmd(string(rest_parts[1], " help ", rest_parts[2]);
                             commands, scope)
        else
            help_show(rest_parts[1]; commands)
        end
    else
        repl_cmd = find_repl_cmd(cmd; warn=true, commands, scope)
        if isnothing(repl_cmd)
        elseif repl_cmd isa ReplCmd{Function}
            repl_cmd.execute(rest)
        elseif repl_cmd isa ReplCmd{Vector{ReplCmd}}
            execute_repl_cmd(rest, commands = repl_cmd.execute, scope = repl_cmd.name)
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

More specifically, the command (`cmd`) being completed is identified and
`cmd.completions(sofar::AbstractString)` called.

Special behaviour is implemented for the help command.
"""
function complete_repl_cmd(line::AbstractString; commands::Vector{ReplCmd}=REPL_CMDS)
    if isempty(line)
        cands = [c.name for c in commands]
        push!(cands, "help")
        (sort(cands), "", true)
    else
        cmd_parts = split(line, limit = 2)
        cmd_name, rest = if length(cmd_parts) == 1
            cmd_parts[1], ""
        else
            cmd_parts
        end
        repl_cmd = find_repl_cmd(cmd_name; commands)
        complete = if !isnothing(repl_cmd) && line != cmd_name
            if repl_cmd.name == "help"
                # This can't be a `repl_cmd.completions(...)` call because we
                # need to access `commands`.
                if startswith(rest, ':') # transformer help
                    filter(t -> startswith(t, rest),
                           string.(':', TRANSFORMER_DOCUMENTATION .|>
                               first .|> last |> unique))
                else # command help
                    [c.name for c in commands if startswith(c.name, rest)]
                end
            else
                repl_cmd.completions(rest)
            end
        else
            all_cmd_names = map(c -> c.name, commands)
            push!(all_cmd_names, "help")
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

if VERSION >= v"1.11-alpha1"
    function REPL.complete_line(::DataCompletionProvider, state::REPL.LineEdit.PromptState; hint::Bool = false)
        # See REPL.jl complete_line(c::REPLCompletionProvider, s::PromptState)
        partial = REPL.beforecursor(state.input_buffer)
        full = REPL.LineEdit.input_string(state)
        if partial != full
            # For now, only complete at end of line
            return (String[], "", false)
        end
        complete_repl_cmd(full)
    end
else
    function REPL.complete_line(::DataCompletionProvider, state::REPL.LineEdit.PromptState)
        # See REPL.jl complete_line(c::REPLCompletionProvider, s::PromptState)
        partial = REPL.beforecursor(state.input_buffer)
        full = REPL.LineEdit.input_string(state)
        if partial != full
            # For now, only complete at end of line
            return (String[], "", false)
        end
        complete_repl_cmd(full)
    end
end

function create_data_mode(repl::REPL.AbstractREPL, base_mode::LineEdit.Prompt)
    prompt_prefix, prompt_suffix = if repl.options.hascolor
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
        complete = DataCompletionProvider(),
        sticky = true)

    data_mode.repl = repl
    history_provider = base_mode.hist
    history_provider.mode_mapping[REPL_NAME] = data_mode
    data_mode.hist = history_provider

    main_keymap = REPL.mode_keymap(base_mode)
    _, search_keymap = LineEdit.setup_search_keymap(history_provider)
    _, prefix_keymap = LineEdit.setup_prefix_keymap(history_provider, data_mode)

    data_mode.on_done =
        REPL.respond(toplevel_execute_repl_cmd, repl, data_mode)

    data_mode.keymap_dict = LineEdit.keymap(Dict{Any, Any}[
        search_keymap,
        main_keymap,
        prefix_keymap,
        LineEdit.history_keymap,
        LineEdit.default_keymap,
        LineEdit.escape_defaults
    ])

    data_mode
end

"""
    init_repl(repl)

Construct the Data REPL `LineEdit.Prompt` and configure it and the REPL to
behave appropriately. Other than boilerplate, this basically consists of:
- Setting the prompt style
- Setting the execution function (`toplevel_execute_repl_cmd`)
- Setting the completion to use `DataCompletionProvider`
"""
function init_repl(repl::REPL.AbstractREPL)
    # With *heavy* inspiration from <https://github.com/MasonProtter/ReplMaker.jl>
    # and Pkg.jl.
    main_mode = repl.interface.modes[1] # Julia mode
    data_mode = create_data_mode(repl, main_mode)
    push!(repl.interface.modes, data_mode)
    function key_action(state, args...)
        if isempty(state) || position(LineEdit.buffer(state)) == 0
            buf = copy(LineEdit.buffer(state))
            LineEdit.transition(state, data_mode) do
                LineEdit.state(state, data_mode).input_buffer = buf
            end
        else
            LineEdit.edit_insert(state, REPL_KEY)
        end
    end
    data_keymap = Dict{Any, Any}(REPL_KEY => key_action)
    main_mode.keymap_dict =
        LineEdit.keymap_merge(main_mode.keymap_dict, data_keymap)
    nothing
end

"""
    find_repl_cmd(cmd::AbstractString; warn::Bool=false,
                  commands::Vector{ReplCmd}=REPL_CMDS,
                  scope::String="Data REPL")

Examine the command string `cmd`, and look for a command from `commands` that is
uniquely identified. Either the identified command or `nothing` will be returned.

Should `cmd` start with `help` or `?` then a `ReplCmd("help", ...)` command is returned.

If `cmd` is ambiguous and `warn` is true, then a message listing all potentially
matching commands is printed.

If `cmd` does not match any of `commands` and `warn` is true, then a warning
message is printed. Additionally, should the named command in `cmd` have more
than a 3/5th longest common subsequence overlap with any of `commands`, then
those commands are printed as suggestions.
"""
function find_repl_cmd(cmd::AbstractString; warn::Bool=false,
                       commands::Vector{ReplCmd}=REPL_CMDS,
                       scope::String="Data REPL")
    replcmds = let candidates = filter(c -> startswith(c.name, cmd), commands)
        if isempty(candidates)
            candidates = filter(c -> issubseq(cmd, c.name), commands)
            if !isempty(candidates)
                char_filtered = filter(c -> startswith(c.name, first(cmd)), candidates)
                if !isempty(char_filtered)
                    candidates = char_filtered
                end
            end
        end
        candidates
    end
    subcommands = Dict{String, Vector{String}}()
    for command in commands
        if command.execute isa Vector{ReplCmd}
            for subcmd in command.execute
                if haskey(subcommands, subcmd.name)
                    push!(subcommands[subcmd.name], command.name)
                else
                    subcommands[subcmd.name] = [command.name]
                end
            end
        end
    end
    all_cmd_names = map(c -> c.name, commands)
    if cmd == "" && "" in all_cmd_names
        replcmds[findfirst("" .== all_cmd_names)]
    elseif length(replcmds) == 0 && (cmd == "?" || startswith("help", cmd)) || length(cmd) == 0
        ReplCmd("help", replace(HELP_CMD_HELP, "<SCOPE>" => scope),
                cmd -> help_show(cmd; commands))
    elseif length(replcmds) == 1
        first(replcmds)
    elseif length(replcmds) > 1 &&
        sum(c -> cmd == c.name, replcmds) == 1 # single exact match
        replcmds[findfirst(c -> c.name == cmd, replcmds)]
    elseif warn && length(replcmds) > 1
        printstyled(" ! ", color=:red, bold=true)
        print("Multiple matching $scope commands: ")
        candidates = [c.name for c in replcmds if c.name != ""]
        for cand in candidates
            highlight_lcs(stdout, cand, String(cmd), before="\e[4m", after="\e[24m")
            cand === last(candidates) || print(", ")
        end
        print('\n')
    elseif warn && haskey(subcommands, cmd)
        printstyled(" ! ", color=:red, bold=true)
        println("The $scope command '$cmd' is not defined.")
        printstyled(" i ", color=:cyan, bold=true)
        println("Perhaps you want the '$(join(subcommands[cmd], '/')) $cmd' subcommand?")
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
