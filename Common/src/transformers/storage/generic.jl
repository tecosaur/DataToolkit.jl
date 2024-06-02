# A selection of fallback methods for various forms of raw file content
# We implement `getstorage` / `putstorage` instead of `storage` to allow
# for specialised implementations of one method but not the other.

function getstorage(storage::S, ::Type{IO}) where {S <: DataStorage}
    if hasmethod(getstorage, Tuple{S, FilePath})
        path = getstorage(storage, FilePath)
        isnothing(path) && return
        !isfile(path) && return
        open(path, "r")
    end
end

function getstorage(storage::S, ::Type{Vector{UInt8}}) where {S <: DataStorage}
    if hasmethod(getstorage, Tuple{S, IO})
        io = getstorage(storage, IO)
        isnothing(io) && return
        read(io)
    end
end

function getstorage(storage::S, ::Type{String}) where {S <: DataStorage}
    if hasmethod(getstorage, Tuple{S, IO})
        io = getstorage(storage, IO)
        isnothing(io) && return
        read(io, String)
    end
end

# We can't really return a `String` or `Vector{UInt8}` that can be
# effectively written to, so we'll just do the `IO` fallback.

function putstorage(storage::S, ::Type{IO}) where {S <: DataStorage}
    if hasmethod(getstorage, Tuple{S, FilePath})
        path = getstorage(storage, FilePath)
        isnothing(path) && return
        open(path, "w")
    end
end
