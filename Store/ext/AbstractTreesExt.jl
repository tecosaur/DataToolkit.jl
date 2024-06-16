module AbstractTreesExt

using DataToolkitStore: MerkleTree
using AbstractTrees

function AbstractTrees.children(mt::MerkleTree)
    if isnothing(mt.children)
        MerkleTree[]
    else
        mt.children
    end
end

function AbstractTrees.printnode(io::IO, mt::MerkleTree)
    print(io, escape_string(mt.path))
    if !isnothing(mt.children)
        print(io, "/")
    end
    print(io, "  ")
    printstyled(io, string(mt.checksum), color=:light_black)
end

end
