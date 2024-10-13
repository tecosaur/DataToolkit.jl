module DataToolkit

import Base as JLBase

using DataToolkitCore
using DataToolkitStore
using DataToolkitCommon
using DataToolkitBase: DataToolkitBase, loadproject!
using DataToolkitREPL

using PrecompileTools

export loadcollection!, dataset, DataSet, @d_str, @data_cmd, @require

macro reexport()
    :(export DataToolkit, loadcollection!, dataset, DataSet, @d_str, @data_cmd, @require)
end

const var"@d_str" = DataToolkitBase.var"@d_str"
const var"@require" = DataToolkitBase.var"@require"
const var"@addpkg" = DataToolkitBase.var"@addpkg"

map((:DataCollection, :DataSet, :DataStorage, :DataLoader, :DataWriter,
     :Identifier, :Plugin, :dataset, :getlayer)) do var
         @eval const $var = DataToolkitCore.$var
end

const Core = DataToolkitCore
const Store = DataToolkitStore
const Common = DataToolkitCommon
const Base = DataToolkitBase
const REPL = DataToolkitREPL

"""
    plugins()

List the currently availible plugins, by name.
"""
plugins() = getfield.(DataToolkitBase.PLUGINS, :name)

include("addpkgs.jl")

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
    project_paths = if isnothing(pathof(mod))
        JLBase.load_path()
    else
        [abspath(pathof(mod), "..", "..")]
    end
    for project_path in project_paths |> reverse
        loadproject!(mod, project_path; force)
    end
end

function __init__()
    if lowercase(get(ENV, "DATA_TOOLKIT_AUTO_INIT", "yes")) ∉ ("0", "false", "no")
        init()
    end
end

@compile_workload init()

end
