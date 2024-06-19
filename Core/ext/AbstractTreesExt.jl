module AbstractTreesExt

using DataToolkitCore
using AbstractTrees

AbstractTrees.children(dataset::DataSet) =
    DataToolkitCore.referenced_datasets(dataset)

AbstractTrees.printnode(io::IO, d::DataSet) = print(io, d.name)

end
