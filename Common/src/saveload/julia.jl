# Example:
#---
# [data.loader]
# driver = "julia"
# type = ["Int"]
# function = "(; inp) -> length(inp)"
# arguments = { inp = "📇DATASET<<somelist::Vector>>" }

function getactfn(transformer::AbstractDataTransformer)
    path = get(transformer, "path", nothing)
    fnstr = get(transformer, "function", nothing)
    loadfn = if !isnothing(path)
        Base.include(transformer.dataset.collection.mod,
                     abspath(dirname(transformer.dataset.collection.path),
                             expanduser(get(transformer, "pathroot", "")),
                             expanduser(path)))
    elseif !isnothing(fnstr)
        Base.eval(transformer.dataset.collection.mod,
                  Meta.parse(strip(fnstr)))
    else
        error("Neither path nor function is provided.")
    end
end

function load(loader::DataLoader{:julia}, ::Nothing, R::Type)
    if isempty(get(loader, "input", ""))
        loadfn = getactfn(loader)
        arguments = Dict{Symbol,Any}(
            Symbol(arg) => val
            for (arg, val) in get(loader, "arguments", Dict())::Dict)
        dir = if isnothing(loader.dataset.collection.path) pwd()
            else dirname(loader.dataset.collection.path) end
        cd(dir) do
            DataToolkitBase.invokepkglatest(loadfn; arguments...)::R
        end
    end
end

function load(loader::DataLoader{:julia}, from::Any, R::Type)
    if !isempty(get(loader, "input", ""))
        desired_type = typeify(QualifiedType(get(loader, "input", "")))
        if from isa desired_type
            loadfn = getactfn(loader)
            arguments = Dict{Symbol,Any}(
                Symbol(arg) => val
                for (arg, val) in get(loader, "arguments", Dict())::Dict)
            dir = if isnothing(loader.dataset.collection.path) pwd()
            else dirname(loader.dataset.collection.path) end
            cd(dir) do
                DataToolkitBase.invokepkglatest(loadfn, from; arguments...)::R
            end
        end
    end
end

function save(writer::DataWriter{:julia}, dest, info)
    writefn = getactfn(writer)
    arguments = Dict{Symbol,Any}(
        Symbol(arg) => val
        for (arg, val) in get(loader, "arguments", Dict())::Dict)
    dir = if isnothing(writer.dataset.collection.path) pwd()
    else dirname(writer.dataset.collection.path) end
    cd(dir) do
        DataToolkitBase.invokepkglatest(writefn, dest, info; arguments...)
    end
end

createpriority(::Type{DataLoader{:julia}}) = 10

function create(::Type{DataLoader{:julia}}, source::String)
    if !isnothing(match(r"\.jl$"i, source)) &&
        isfile(abspath(dirname(dataset.collection.path), expanduser(source)))
        Dict{String, Any}("path" => source)
    end
end
