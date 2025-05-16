# A selection of fallback methods for various forms of raw file content
# We implement `getstorage` / `putstorage` instead of `storage` to allow
# for specialised implementations of one method but not the other.

function storage(store::S, ::Type{IO}; write = false) where {S <: DataStorage}
    path = storage(store, FilePath; write)
    isnothing(path) && return
    !isfile(string(path)) && return
    open(string(path); write)
end

function getstorage(store::S, ::Type{Vector{UInt8}}) where {S <: DataStorage}
    io = storage(store, IO; write = false)
    isnothing(io) && return
    read(io)
end

function getstorage(store::S, ::Type{String}) where {S <: DataStorage}
    io = storage(store, IO; write = false)
    !isnothing(io) && return read(io, String)
    bytes = storage(store, Vector{UInt8}; write = false)
    !isnothing(bytes) && return String(copy(bytes))
    nothing
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
