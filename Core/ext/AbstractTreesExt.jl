module AbstractTreesExt

using DataToolkitCore
using AbstractTrees

AbstractTrees.children(dataset::DataSet) =
    DataToolkitCore.referenced_datasets(dataset)

AbstractTrees.printnode(io::IO, d::DataSet) =
    print(io, @advise d string(Identifier(d, nothing)))

end
