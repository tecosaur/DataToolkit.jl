module DataToolkit

using DataToolkitBase
using DataToolkitCommon

export loadcollection!, dataset, DataSet, @d_str

const Base = DataToolkitBase
const Common = DataToolkitCommon

const var"@use" = DataToolkitBase.var"@use"
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
    :(read(dataset($ident)))
end

"""
    init(mod::Module=Main; force::Bool=false)
Load the `mod`-local `Data.toml` if it exists.
When `mod` is `Main`, every `Data.toml` on the load path is loaded.
Unless `force` is set, the data collection is soft-loaded.
"""
function init(mod::Module=Main.Base.Main; force::Bool=false)
    project_paths = if isnothing(pathof(mod))
        Main.Base.load_path()
    else
        [abspath(pathof(mod), "..", "..")]
    end
    for project_path in project_paths
        if !isdir(project_path)
            project_path = dirname(project_path)
        end
        project_data = joinpath(project_path, "Data.toml")
        if isfile(project_data)
            loadcollection!(project_data, mod, soft=!force)
        end
    end
end

function __init__()
    if lowercase(get(ENV, "DATA_TOOLKIT_AUTO_INIT", "yes")) ∉ ("0", "false", "no")
        init()
    end
end

end
