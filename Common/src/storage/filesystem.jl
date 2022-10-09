getpath(storage::DataStorage{:filesystem}) =
    abspath(dirname(storage.dataset.collection.path),
            @something(expanduser(get(storage, "path")) ,
                       error("No path")))

function storage(storage::DataStorage{:filesystem}, ::Type{IO};
                 write::Bool=false)
    file = getpath(storage)
    if write || isfile(file)
        open(file; write)
    end
end

function storage(storage::DataStorage{:filesystem}, ::Type{Vector{UInt8}}; write::Bool=false)
    write && error("Cannot represent file as a writable string.")
    read(getpath(storage))
end

function storage(storage::DataStorage{:filesystem}, ::Type{String}; write::Bool=false)
    write && error("Cannot represent file as a writable string.")
    read(getpath(storage), String)
end

supportedtypes(::Type{<:DataStorage{:filesystem, <:Any}}) =
    QualifiedType.([IO, Vector{UInt8}, String])
