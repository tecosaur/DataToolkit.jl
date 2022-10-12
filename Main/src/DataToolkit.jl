module DataToolkit

using DataToolkitBase
using DataToolkitCommon

export loadcollection!, dataset, DataSet

const var"@use" = DataToolkitBase.var"@use"
const var"@addpkg" = DataToolkitBase.var"@addpkg"

map((:DataCollection, :DataSet, :DataStorage, :DataLoader, :DataWriter,
     :Identifier, :Plugin, :getlayer, :PLUGINS, :EXTRA_PACKAGES)) do var
         @eval const $var = DataToolkitBase.$var
end

include("addpkgs.jl")

"""
    init(force::Bool=false)
Load the project-local `Data.toml` if it exists.
Unless `force` is set, the data collection is soft-loaded.
"""
function init(mod::Module=Base.Main; force::Bool=false)
    project_dir = first(Base.load_path())
    if !isdir(project_dir)
        project_dir = dirname(project_dir)
    end
    project_data = joinpath(project_dir, "Data.toml")
    if isfile(project_data)
        loadcollection!(project_data, mod, soft=!force)
    end
end

function __init__()
    if lowercase(get(ENV, "DATA_TOOLKIT_AUTO_INIT", "yes")) ∉ ("0", "false", "no")
        init()
    end
end

end
