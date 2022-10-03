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

function load(loader::DataLoader{:nested}, from::Any, T::Type)
    mapreduce(spec -> let subloader = DataLoader(loader.dataset, spec)
                  (subloader, convert(Type, first(subloader.support))) end,
              (value, (subloader, as)) -> load(subloader, value, as),
              get(loader, "loaders", Dict{String, Any}[]),
              init=from)::T
end
