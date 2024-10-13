module DataToolkitBase

using DataToolkitCore
using DataToolkitCommon
using DataToolkitStore

export @d_str, @load, @require, @addpkg

const var"@require" = DataToolkitCore.var"@require"
const var"@addpkg" = DataToolkitCore.var"@addpkg"

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

function loadproject!(mod::Module, projpath::String; force::Bool=false)
    function tryloadcollection!(path::String, m::Module; soft::Bool)
        try
            loadcollection!(path, m; soft)
        catch err
            @error "Failed to load $path" exception=(err, catch_backtrace())
        end
    end
    if !isdir(projpath)
        projpath = dirname(projpath)
    end
    # Skip packages when `init(Main)` called.
    if mod === Main && isfile(joinpath(projpath, "Project.toml"))
        data = Base.parsed_toml(joinpath(projpath, "Project.toml"))
        ispkg = haskey(data, "name") && haskey(data, "uuid") &&
            haskey(data, "version") && isfile(joinpath(
                projpath, "src", data["name"] * ".jl"))
        ispkg && return
    end
    # Load Data.d/*.toml
    data_dir = joinpath(projpath, "Data.d")
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
    data_file = joinpath(projpath, "Data.toml")
    if isfile(data_file)
        isdir(data_dir) && @warn "($mod) consider placing Data.toml file inside Data.d directory"
        tryloadcollection!(data_file, mod, soft=!force)
    end
end

macro load()
    :(loadproject!(@__MODULE__, pkgdir(@__MODULE__)))
end

end
