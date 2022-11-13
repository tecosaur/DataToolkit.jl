using REPL

# ------------------
# Terminal interaction utilities
# ------------------

"""
The color that should be used for question text presented in a REPL context.
"""
const REPL_QUESTION_COLOR = :light_magenta

"""
The color that should be set for user response text in a REPL context.
"""
const REPL_USER_INPUT_COLOUR = :light_yellow

"""
    prompt(question::AbstractString)
Interactively ask `question` and return the response string.

### Example

```julia-repl
julia> prompt("What colour is the sky? ")
What colour is the sky? Blue
"Blue"
```
"""
function prompt(question::AbstractString)
    printstyled(question, color=REPL_QUESTION_COLOR)
    get(stdout, :color, false) && print(Base.text_colors[REPL_USER_INPUT_COLOUR])
    response = readline(stdin)
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
                                   path, DataAdviceAmalgamation(plugins),
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
        println("directory 'dirname($path)' does not exist")
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

    if ismissing(name)
        name = if basename(path) == "Data.toml"
            path |> dirname |> basename
        else
            first(splitext(basename(path)))
        end
        response = prompt(" Name [$(name)]: ")
        if !isempty(response)
            name = response
        end
    end

    newcollection = init(name, path)
    nothing
end
