module DataToolkit

using DataToolkitBase
using DataToolkitCommon

export loadcollection!, dataset, DataSet

"""
    init()
Load the project-local `Data.toml` if it exists.
"""
function init()
    project_dir = first(Base.load_path())
    if !isdir(project_dir)
        project_dir = dirname(project_dir)
    end
    project_data = joinpath(project_dir, "Data.toml")
    if isfile(project_data)
        loadcollection!(project_data)
    end
end

function __init__()
    init()
end

end
