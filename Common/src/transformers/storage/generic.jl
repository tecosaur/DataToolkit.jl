# A selection of fallback methods for various forms of raw file content
# We implement `getstorage` / `putstorage` instead of `storage` to allow
# for specialised implementations of one method but not the other.

function storage(store::S, ::Type{IO}; write::Bool = false) where {S <: DataStorage}
    ioform = providedform(store, IO; write)
    isnothing(ioform) || return ioform
    path = storage(store, FilePath; write)
    if !isnothing(path) && (write || isfile(string(path)))
        # `truncate` so a shorter rewrite leaves no stale tail (it defaults off).
        return open(string(path); write, truncate = write, read = !write)
    end
    bytes = providedform(store, Vector{UInt8}; write)
    !isnothing(bytes) && return IOBuffer(bytes)
    str = providedform(store, String; write)
    !isnothing(str) && return IOBuffer(str)
    nothing
end

function getstorage(store::S, ::Type{Vector{UInt8}}) where {S <: DataStorage}
    io = storage(store, IO; write = false)
    !isnothing(io) && return try read(io) finally close(io) end
    str = providedform(store, String)
    !isnothing(str) && return Vector{UInt8}(str)
    nothing
end

function getstorage(store::S, ::Type{String}) where {S <: DataStorage}
    io = storage(store, IO; write = false)
    !isnothing(io) && return try read(io, String) finally close(io) end
    bytes = providedform(store, Vector{UInt8})
    !isnothing(bytes) && return String(copy(bytes))
    nothing
end

# Fetch form `T` via a `get`/`putstorage` method the driver defines itself.
# The fallbacks delegate here rather than to each other (which would recurse),
# so a method shared with the bare `DataStorage` — i.e. a fallback — doesn't
# count as driver-provided.
function providedform(store::S, ::Type{T}; write::Bool = false) where {S <: DataStorage, T}
    driverdefined(f) =
        hasmethod(f, Tuple{S, Type{T}}) &&
        (!hasmethod(f, Tuple{DataStorage, Type{T}}) ||
         which(f, Tuple{S, Type{T}}) !== which(f, Tuple{DataStorage, Type{T}}))
    if write && driverdefined(putstorage)
        putstorage(store, T)
    elseif !write && driverdefined(getstorage)
        getstorage(store, T)
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
