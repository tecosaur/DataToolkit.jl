module DataToolkitCommon

using DataToolkitBase
import DataToolkitBase: load, save, storage, getstorage, putstorage

using Dates

include("storage/raw.jl")
include("storage/web.jl")
include("storage/filesystem.jl")

include("storage/store/hash.jl")

include("saveload/passthrough.jl")
include("saveload/delim.jl")
include("saveload/csv.jl")

include("plugins/defaults.jl")

function __init__()
    project_dir = first(Base.load_path())
    if !isdir(project_dir)
        project_dir = dirname(project_dir)
    end
    project_data = joinpath(project_dir, "Data.toml")
    if isfile(project_data)
        loadcollection!(project_data)
    end

    @addpkg Downloads      "f43a241f-c20a-4ad4-852c-f6b1247861c6"
    @addpkg DelimitedFiles "8bb1440f-4735-579b-a4ab-409b98df4dab"
    @addpkg CSV            "336ed68f-0bac-5ca0-87d4-7b16caf5d00b"
    @addpkg JSON3          "0f8b85d8-7281-11e9-16c2-39a750bddbf1"

    push!(PLUGINS, defaults_plugin)
end

end
