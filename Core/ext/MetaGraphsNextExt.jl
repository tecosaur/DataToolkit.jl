module MetaGraphsNextExt

using DataToolkitCore: DataCollection, DataSet, referenced_datasets, Identifier

using MetaGraphsNext
using MetaGraphsNext.Graphs
import MetaGraphsNext.MetaGraph

function MetaGraph(datasets::Vector{DataSet})
    graph = MetaGraphsNext.MetaGraph(DiGraph(), label_type=String, vertex_data_type=DataSet)
    labels = Dict{DataSet, String}()
    function getlabel(ds::DataSet)
        get!(labels, ds) do
            replace(sprint(io -> show(IOContext(io, :data_collection => ds.collection),
                                      MIME("text/plain"), Identifier(ds))),
                    "■:" => "")
        end
    end
    seen = Set{DataSet}()
    queue = copy(datasets)
    while !isempty(queue)
        ds = popfirst!(queue)
        ds in seen && continue
        push!(seen, ds)
        haskey(labels, ds) || add_vertex!(graph, getlabel(ds), ds)
        deps = referenced_datasets(ds)
        for dep in deps
            haskey(labels, dep) || add_vertex!(graph, getlabel(dep), dep)
            add_edge!(graph, labels[dep], labels[ds])
            push!(queue, dep)
        end
    end
    graph
end

MetaGraph(ds::DataSet) = MetaGraph([ds])
MetaGraph(dc::DataCollection) = MetaGraph(dc.datasets)

end
