function search(input::AbstractString)
    if isempty(input)
        printstyled(" ! ", color=:yellow, bold=true)
        println("Provide a search string")
    else
        candidates = Tuple{DataSet, String, Int}[]
        searchstack = STACK
        caseinsensitive = all(!isuppercase, input)
        if ':' in input
            collection, _ = split(input, ':', limit=2)
            searchstack = [DataToolkitBase.getlayer(if !isempty(collection) collection end)]
        end
        for collection in STACK
            for dataset in collection.datasets
                identstr = @advise collection string(Identifier(dataset))
                identstr = replace(identstr, collection.name * ':' => "", count=1)
                if caseinsensitive
                    identstr = lowercase(identstr)
                end
                score = DataToolkitBase.stringdist(input, identstr) -
                    max(0, length(identstr) - length(input))
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
                show(stdout, MIME("text/plain"), Identifier(dataset); collection=dataset.collection)
            end
            print('\n')
        end
    end
end
