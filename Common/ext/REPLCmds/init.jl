const INIT_DOC = md"""
Initialise a new data collection

Optionally, a data collection name and path can be specified with the forms:

    data> init [NAME]
    data> init [PATH]
    data> init [NAME] [PATH]
    data> init [NAME] at [PATH]

Plugins can also be specified by adding a `with` argument,

    data> init [...] with PLUGINS...

To omit the default set of plugins, put `with -n` instead, i.e.

    data> init [...] with -n PLUGINS...

# Usage

    data> init
    data> init /tmp/test
    data> init test at /tmp/test
    data> init test at /tmp/test with plugin1 plugin2
"""

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
    elseif first(peelword(rest)) == "with"
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

    path = if isempty(rest) || first(peelword(rest)) == "with"
        if !isnothing(Base.active_project(false)) &&
            !isfile(joinpath(dirname(Base.active_project(false)), "Data.toml")) &&
            confirm_yn(" Create Data.toml for current project?", true)
            dirname(Base.active_project(false))
        else
            prompt(" Path to Data TOML file: ",
                   joinpath(if !isnothing(Base.active_project(false))
                                dirname(Base.active_project(false))
                            else pwd() end, "$(coalesce(name, "Data")).toml"))
        end
    else
        path, rest = peelword(rest)
        path
    end |> expanduser |> abspath

    plugins = copy(DataToolkitBase.DEFAULT_PLUGINS)
    if ((_, rest) = peelword(rest)) |> first == "with"
        extra_plugins = split(rest, r", *| +")
        if "-n" in extra_plugins
            plugins = String[]
            deleteat!(extra_plugins, findfirst("-n" .== extra_plugins)::Int)
        end
        append!(plugins, extra_plugins)
    end

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

    DataToolkitBase.init(name, path; plugins)
    nothing
end
