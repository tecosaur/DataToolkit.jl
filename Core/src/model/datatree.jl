using AbstractTrees

function AbstractTrees.children(dataset::DataSet)
    dataset_references = Identifier[]
    add_datasets!(dataset_references, dataset.parameters)
    for paramsource in vcat(dataset.storage, dataset.loaders, dataset.writers)
        add_datasets!(dataset_references, paramsource.parameters)
    end
    resolve.(Ref(dataset.collection), dataset_references,
             resolvetype=false)
end

printnode(io::IO, d::DataSet) = print(io, d.name)

add_datasets!(acc::Vector{Identifier}, props::Dict) =
    for val in values(props)
        add_datasets!(acc, val)
    end

add_datasets!(acc::Vector{Identifier}, props::Vector) =
    for val in props
        add_datasets!(acc, val)
    end

add_datasets!(acc::Vector{Identifier}, ident::Identifier) =
    push!(acc, ident)

add_datasets!(::Vector{Identifier}, ::Any) = nothing
