# Example:
#---
# [data.loader]
# driver = "nested"
# support = ["DataFrames.DataFrame"] # final supported data
# loaders = [
#   { driver = "gzip", support = "IO" },
#   { driver = "csv", support = "DataFrames.DataFrame"}
# ]
# # alternative
# loaders = [ "gzip", "csv" ]

function load(loader::DataLoader{:nested}, from::Any, ::Type{T}) where {T}
    subloaders = map(spec -> DataLoader(loader.dataset, spec),
                  get(loader, "loaders", Dict{String, Any}[]))
    types = loadtypepath(subloaders, typeof(from), T)
    reduce((value, (subloader, as)) -> load(subloader, value, as),
           zip(subloaders, types), init=from)::T
end

"""
    loadtypepath(subloaders::Vector{DataLoader}, targettype::Type)
Return the sequence of types that the `subloaders` must be asked for to finally
produce `targettype` from an initial `fromtype`. If this is not possible,
`nothing` is returned instead.
"""
function loadtypepath(subloaders::Vector{DataLoader}, fromtype::Type, targettype::Type)
    toploader = last(subloaders)
    supporttypes = filter(!isnothing, convert.(Type, toploader.support))
    if length(subloaders) > 1
        potentialmethods =
            [methods(load, Tuple{typeof(toploader), Any, Type{suptype}}).ms
             for suptype in supporttypes
                 if suptype <: targettype] |> Iterators.flatten |> unique
        midtypes = [m.sig.types[3] for m in potentialmethods]
        subpaths = filter(!isnothing,
                          [loadtypepath(subloaders[1:end-1], fromtype, midtype)
                           for midtype in midtypes])
        if !isempty(subpaths)
            vcat(first(subpaths), targettype)
        end
    else
        ms = methods(load, Tuple{typeof(toploader), fromtype, Type{targettype}})
        if !isempty(ms)
            targettype
        end
    end
end
