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
            identifier = parse(Identifier, first(split(sofar, "::")))
            types = map(l -> l.type, resolve(identifier).loaders) |>
                Iterators.flatten .|> string |> unique
            string.(string(identifier), "::", types)
        elseif !isnothing(match(r"^[^:]+:", sofar))
            layer, _ = split(sofar, ':', limit=2)
            filter(o -> startswith(o, sofar),
                   string.(layer, ':',
                           unique(getproperty.(
                               getlayer(layer).datasets, :name))))
        else
            filter(o -> startswith(o, sofar),
                   vcat(getproperty.(STACK, :name) .* ':',
                        getproperty.(getlayer().datasets, :name) |> unique))
        end
    catch _
        String[]
    end |> options -> sort(filter(o -> startswith(o, sofar), options), by=natkeygen)
end

function complete_dataset_or_collection(sofar::AbstractString)
    cands = complete_collection(sofar)
    append!(cands, complete_dataset(sofar))
    sort!(cands, by=natkeygen)
    cands
end

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
            "^D" => (_...) -> throw(InterruptException()),
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

Interactively ask `question`, only accepting `options` keys as answers.
All keys are converted to lower case on input. If `default` is not nothing and
'RET' is hit, then `default` will be returned.

Should '^C' be pressed, an InterruptException will be thrown.
"""
function prompt_char(question::AbstractString, options::Vector{Char},
                     default::Union{Char, Nothing}=nothing)
    printstyled(question, color=REPL_QUESTION_COLOR)
    term_env = get(ENV, "TERM", @static Sys.iswindows() ? "" : "dumb")
    term = REPL.Terminals.TTYTerminal(term_env, stdin, stdout, stderr)
    REPL.Terminals.raw!(term, true)
    char = '\x01'
    while char ∉ options
        char = lowercase(Char(REPL.TerminalMenus.readkey(stdin)))
        if char == '\r' && !isnothing(default)
            char = default
        elseif char == '\x03' # ^C
            print("\e[m^C\n")
            throw(InterruptException())
        end
    end
    REPL.Terminals.raw!(term, false)
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

function DataToolkitCore.interactiveparams(::REPL.REPLDisplay, spec::Vector, driver::Symbol)
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
