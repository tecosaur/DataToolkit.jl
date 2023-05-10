module AbstractTreesExt

using DataToolkitBase

DataToolkitBase.add_datasets!(acc::Vector{Identifier}, storage::DataStorage{:passthrough}) =
    DataToolkitBase.add_datasets!(acc, parse(Identifier, get(storage, "source")))

end
