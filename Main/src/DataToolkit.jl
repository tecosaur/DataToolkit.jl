module DataToolkit

import Base as JLBase

using DataToolkitBase
using DataToolkitCommon

using PrecompileTools

export loadcollection!, dataset, DataSet, @d_str, @data_cmd, @import

macro reexport()
    :(export DataToolkit, loadcollection!, dataset, DataSet, @d_str, @data_cmd, @import)
end

const Base = DataToolkitBase
const Common = DataToolkitCommon

const var"@import" = DataToolkitBase.var"@import"
const var"@addpkg" = DataToolkitBase.var"@addpkg"

map((:DataCollection, :DataSet, :DataStorage, :DataLoader, :DataWriter,
     :Identifier, :Plugin, :getlayer)) do var
         @eval const $var = DataToolkitBase.$var
end

"""
    plugins()

List the currently availible plugins, by name.
"""
plugins() = getfield.(DataToolkitBase.PLUGINS, :name)

include("addpkgs.jl")

"""
    @d_str -> loaded data

Shorthand for loading a dataset in the default format,
`d"iris"` is equivalent to `read(dataset("iris"))`.
"""
macro d_str(ident::String)
    quote
        ref = parse(Identifier, $ident)
        if !isnothing(ref.type)
            resolve(ref)
        else
            read(resolve(ref, resolvetype=false))
        end
    end
end

"""
    @data_cmd -> Data REPL command result

Proxy for running the command in the Data REPL,
e.g. ```data`config set demo 1` ``` is equivalent to `data> config set demo 1`.
"""
macro data_cmd(line::String)
    :(DataToolkitBase.toplevel_execute_repl_cmd($line))
end

"""
    init(mod::Module=Main; force::Bool=false)

Load the `mod`-local `Data.toml` if it exists.
When `mod` is `Main`, every `Data.toml` on the load path is loaded, except for
`Data.toml`s within packages' projects.
Unless `force` is set, the data collection is soft-loaded.

A `Data.d` directory can be used in place of a `Data.toml`, in which case
every toml file within it will be read. Mixing `Data.d/*.toml` and `Data.toml`
is discouraged.
"""
function init(mod::Module=Main; force::Bool=false)
    function tryloadcollection!(path::String, m::Module; soft::Bool)
        try
            loadcollection!(path, m; soft)
        catch err
            @error "Failed to load $path" err
        end
    end
    project_paths = if isnothing(pathof(mod))
        JLBase.load_path()
    else
        [abspath(pathof(mod), "..", "..")]
    end
    for project_path in project_paths |> reverse
        if !isdir(project_path)
            project_path = dirname(project_path)
        end
        # Skip packages when `init(Main)` called.
        if mod === Main && isfile(joinpath(project_path, "Project.toml"))
            data = JLBase.parsed_toml(joinpath(project_path, "Project.toml"))
            ispkg = haskey(data, "name") && haskey(data, "uuid") &&
                haskey(data, "version") && isfile(joinpath(
                    project_path, "src", data["name"] * ".jl"))
            ispkg && continue
        end
        # Load Data.d/*.toml
        data_dir = joinpath(project_path, "Data.d")
        if isdir(data_dir)
            dfiles = filter(f -> endswith(f, ".toml"),
                            readdir(data_dir, join=true))
            for dfile in filter(f -> basename(f) != "Data.toml", dfiles)
                tryloadcollection!(dfile, mod, soft=!force)
            end
            # Load Data.toml last so that is is first in the stack.
            joinpath(data_dir, "Data.toml") in dfiles &&
                tryloadcollection!("Data.d/Data.toml", mod, soft=!force)
        end
        # Load Data.toml
        data_file = joinpath(project_path, "Data.toml")
        if isfile(data_file)
            isdir(data_dir) && @warn "($mod) consider placing Data.toml file inside Data.d directory"
            tryloadcollection!(data_file, mod, soft=!force)
        end
    end
end

function __init__()
    if lowercase(get(ENV, "DATA_TOOLKIT_AUTO_INIT", "yes")) ∉ ("0", "false", "no")
        init()
    end
end

@compile_workload init()

end
