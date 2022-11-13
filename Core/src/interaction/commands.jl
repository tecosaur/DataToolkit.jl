# ------------------
# Terminal interaction utilities
# ------------------

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
