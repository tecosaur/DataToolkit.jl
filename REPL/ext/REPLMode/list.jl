const LIST_DOC = md"""
List the datasets in a certain collection

By default, the datasets of the active collection are shown.

## Usage

    data> list (lists dataset of the active collection)
    data> list COLLECTION
"""

function repl_list(io::IO, collection_str::AbstractString; maxwidth::Int=displaysize(io)[2])
    if isempty(STACK)
        printstyled(io, " ! ", color=:yellow, bold=true)
        println(io, "The data collection stack is empty")
    else
        collection = if isempty(collection_str)
            getlayer()
        else
            getlayer(collection_str)
        end
        refresh!(collection)
        table_rows = displaytable(
            ["Dataset", "Description"],
            if isempty(collection.datasets)
                Vector{Any}[]
            else
                map(sort(collection.datasets, by = d -> natkeygen(d.name))) do dataset
                    [dataset.name,
                     first(split(lstrip(get(dataset, "description", "")),
                                 '\n', keepempty=true))]
                end
            end; maxwidth)
        for row in table_rows
            print(io, ' ', row, '\n')
        end
    end
end
