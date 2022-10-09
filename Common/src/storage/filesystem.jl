function storage(storage::DataStorage{:filesystem}, ::Type{IO};
                 write::Bool=false)
    file = abspath(dirname(storage.dataset.collection.path),
                   @something get(storage, "path") error("No path"))
    if write || isfile(file)
        open(file; write)
    end
end

function storage(storage::DataStorage{:filesystem}, ::Type{Vector{UInt8}}; write::Bool=false)
    write && error("Cannot represent file as a writable string.")
    file = abspath(dirname(storage.dataset.collection.path),
                   @something get(storage, "path") error("No path"))
    read(file)
end

function storage(storage::DataStorage{:filesystem}, ::Type{String}; write::Bool=false)
    write && error("Cannot represent file as a writable string.")
    file = abspath(dirname(storage.dataset.collection.path),
                   @something get(storage, "path") error("No path"))
    read(file, String)
end

supportedtypes(::Type{<:DataStorage{:filesystem, <:Any}}) =
    QualifiedType.([IO, Vector{UInt8}, String])
