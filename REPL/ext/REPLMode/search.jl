const SEARCH_DOC = md"""
Search for a particular data collection

## Usage

    data> search TEXT...
"""

function search(input::AbstractString)
    if isempty(input)
        printstyled(" ! ", color=:yellow, bold=true)
        println("Provide a search string")
    else
        candidates = Tuple{DataSet, String, Int}[]
        searchstack = STACK
        term = input
        if ':' in input
            cname, term = split(input, ':', limit=2)
            searchstack = try [getlayer(if !isempty(cname) cname end)] catch err
                err isa IdentifierException || rethrow()
                printstyled(" ! ", color=:red, bold=true)
                return println("Could not resolve collection '$cname'")
            end
        end
        caseinsensitive = all(!isuppercase, term)
        for collection in searchstack
            refresh!(collection)
            for dataset in collection.datasets
                identstr = @advise collection string(Identifier(dataset))
                identstr = replace(identstr, something(collection.name, "") * ':' => "", count=1)
                if caseinsensitive
                    identstr = lowercase(identstr)
                end
                score = DataToolkitCore.stringdist(term, identstr) -
                    max(0, length(identstr) - length(term))
                push!(candidates, (dataset, identstr, score))
            end
        end
        if isempty(candidates)
            printstyled(" ! ", color=:yellow, bold=true)
            println("No data sets to search")
        else
            sort!(candidates, by=c -> (last(c), length(c[2])))
            cutoff = if last(first(candidates)) == 0
                0
            else
                max(ceil(last(first(candidates)) * 1.25),
                    last(candidates[min(10, end÷3)]))
            end
            filter!(c -> last(c) <= cutoff, candidates)
            print(" ", length(candidates), " result",
                  ifelse(length(candidates) == 1, "", "s"), ":")
            for (dataset, _, _) in candidates
                print("\n  ")
                show(IOContext(stdout, :data_collection => dataset.collection),
                     MIME("text/plain"), Identifier(dataset))
            end
            print('\n')
        end
    end
end
