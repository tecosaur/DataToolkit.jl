# This is only a small bit of logic/complication, but it pops up
# in quite a few different places so I think it's worth having a single
# implementation of it, and thus ensuring it's handled consistently.

const COLLECTION_CWD_WARNED = Set{UUID}()

"""
    dirof(collection::DataCollection)

Return the root directory for `collection`. In most cases, this will simply be
the directory of the collection file, the two exceptions being:
- When the directory is `"Data.d"`, in which case the parent directory is given
- When `collection` has no path, in which case the current working directory is used
  and a warning emitted (once only per collection).
"""
function dirof(collection::DataCollection)
    if isnothing(collection.path)
        if collection.uuid ∉ COLLECTION_CWD_WARNED
            push!(COLLECTION_CWD_WARNED, collection.uuid)
            @warn "Collection $(sprint(show, collection.name)) ($(collection.uuid)) \
                   does not have a path, using the current working directory ($(pwd()))"
        end
        pwd()
    elseif collection.path |> dirname |> basename == "Data.d"
        collection.path |> dirname |> dirname
    else
        collection.path |> dirname
    end
end
