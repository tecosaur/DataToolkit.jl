module DataToolkit

using DataToolkitBase
using DataToolkitCommon

export loadcollection!, dataset, DataSet

"""
    init(force::Bool=false)
Load the project-local `Data.toml` if it exists.
Unless `force` is set, the data collection is soft-loaded.
"""
function init(force::Bool=false)
    project_dir = first(Base.load_path())
    if !isdir(project_dir)
        project_dir = dirname(project_dir)
    end
    project_data = joinpath(project_dir, "Data.toml")
    if isfile(project_data)
        loadcollection!(project_data, soft=!force)
    end
end

function __init__()
    init()
end

end
