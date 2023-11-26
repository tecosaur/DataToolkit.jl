module AbstractTreesExt

using DataToolkitBase
using AbstractTrees

AbstractTrees.children(dataset::DataSet) =
    DataToolkitBase.referenced_datasets(dataset)

AbstractTrees.printnode(io::IO, d::DataSet) = print(io, d.name)

end
