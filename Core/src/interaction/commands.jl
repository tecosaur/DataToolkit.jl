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
