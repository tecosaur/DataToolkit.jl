"""
Cache IO from data storage backends.
"""
const STORE_PLUGIN = Plugin("store", [
    function (post::Function, f::typeof(storage), storer::DataStorage, as::Type; write::Bool)
        global INVENTORY
        # Get any applicable cache file
        source = getsource(storer)
        file = storefile(storer)
        if !shouldstore(storer) || write
            # If the store is invalid (should not be stored, or about to be
            # written to), then it should be removed before proceeding as
            # normal.
            if !isnothing(source)
                index = findfirst(==(source), INVENTORY.sources)
                !isnothing(index) && deleteat!(INVENTORY.sources, index)
            end
            (post, f, (storer, as), (; write))
        elseif !isnothing(file)
            # If using a cache file, ensure the parent collection is registered
            # as a reference.
            update_source(source, storer)
            if as === IO || as === IOStream
                (post, identity, (open(file, "r"),))
            elseif as === FilePath
                (post, identity, (FilePath(file),))
            else
                (post, f, (storer, as), (; write))
            end
        elseif as == IO || as == IOStream
            # Try to get it as a file, because that avoids
            # some potential memory issues (e.g. large downloads
            # which exceed memory limits).
            tryfile = storage(storer, FilePath; write)
            if !isnothing(tryfile)
                io = open(storesave(storer, FilePath, tryfile), "r")
                (post, identity, (io,))
            else
                (post ∘ storesave(storer, as), f, (storer, as), (; write))
            end
        elseif as === FilePath
            (post ∘ storesave(storer, as), f, (storer, as), (; write))
        else
            (post, f, (storer, as), (; write))
        end
    end])
