# Example:
#---
# [data.loader]
# driver = "julia"
# support = ["Int"]
# function = "(; inp) -> length(inp)"
# arguments = { inp = "💾DATASET<<<somelist::Vector>>>" }

function getactfn(transformer::AbstractDataTransformer)
    path = get(transformer, "path", nothing)
    fnstr = get(transformer, "function", nothing)
    loadfn = if !isnothing(path)
        Base.include(Main, abspath(dirname(transformer.dataset.collection.path),
                                   path))
    elseif !isnothing(fnstr)
        Base.eval(Main, Meta.parse(strip(fnstr)))
    else
        error("Neither path nor function is provided.")
    end
end

function load(loader::DataLoader{:julia}, ::Nothing, R::Type)
    loadfn = getactfn(loader)
    arguments = Dict{Symbol,Any}(
        Symbol(arg) => val
        for (arg, val) in get(loader, "arguments")::Dict)
    Base.invokelatest(loadfn; arguments...)::R
end

function save(writer::DataWriter{:julia}, dest, info)
    writefn = getactfn(writer)
    Base.invokelatest(writefn, dest, info)
end
