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

# For handling saving to a file robustly

is_store_target(::Any) = false

function approximate_store_dest end

"""
    savetofile(savefn::Function, storage::DataStorage) -> FilePath

Save the contents of `storage` to a file using `savefn`.

Given a function that will save `storage` to a file, taking the target path as
the single argument, this function will save the contents of `storage` to a file,
and return the path to the file.

Special care is taken to:
- reduce potential file copying
- avoid returning partial files
- cleanup temporary files at the end of the Julia session
"""
function savetofile(savefn::Function, storage::DataStorage)
    if is_store_target(storage)
        refdest = invokelatest(approximate_store_dest, storage)
        miliseconds = floor(Int, 1000 * time())
        partfile = string(refdest, '-', miliseconds, ".part")
        tmpfile = string(refdest, '-', miliseconds, ".tmp")
        isdir(dirname(tmpfile)) || mkpath(dirname(tmpfile))
        atomic_write(savefn, tmpfile, partfile)
        FilePath(tmpfile)
    else
        tmpfile = tempname()
        @static if isdefined(Base.Filesystem, :temp_cleanup_later)
            Base.Filesystem.temp_cleanup_later(tmpfile)
        end
        savefn(tmpfile)
        FilePath(tmpfile)
    end
end
