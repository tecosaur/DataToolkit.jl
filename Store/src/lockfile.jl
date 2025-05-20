"""
    LockFile(path::String) -> LockFile

A file-based lock that can be used to synchronise access to a resource across
multiple processes. The lock is implemented using a file at `path` that is
created when the lock is acquired and deleted when the lock is released.
"""
struct LockFile <: Base.AbstractLock
    path::String
    owned::ReentrantLock
end

function LockFile(prefix::String, target)
    # It's well worth using the `runtime` dir for a lockfile, as beyond it being
    # appropriate on Linux it's ususally a tempfs volume. This means it's an in-memory
    # filesystem, ~halving the time that `unlock(lock(::LockFile))` takes (10μs → 5μs)
    # and eliminating the risk of running into any filesystem synchronisation issues.
    path = BaseDirs.User.runtime(
        PROJECT_SUBPATH,
        prefix * "-" * string(hash(target), base=32) * ".lock")
    LockFile(path, ReentrantLock())
end

function Base.islocked(lf::LockFile)
    islocked(lf.owned) && return true
    isfile(lf.path) || return false
    pid = open(io -> if eof(io) 0 else read(io, Int) end, lf.path)
    if iszero(@ccall uv_kill(pid::Cint, 0::Cint)::Cint)
        true
    else
        rm(lf.path, force=true)
        false
    end
end

function Base.trylock(lf::LockFile)
    islocked(lf.owned) && return trylock(lf.owned)
    islocked(lf) && return false
    try
        ispath(dirname(lf.path)) || mkpath(dirname(lf.path))
        write(lf.path, UInt(getpid()))
        chmod(lf.path, 0o444)
    catch _
        return false
    end
    lock(lf.owned)
    true
end

function Base.lock(lf::LockFile)
    backoff = 0.00001 # 10μs, given that it takes 5μs lock + unlock on my machine
    while !trylock(lf)
        quicksleep(backoff)
        backoff = min(0.05, backoff * 2)
    end
end

function Base.unlock(lf::LockFile)
    unlock(lf.owned)
    if !islocked(lf.owned)
        rm(lf.path, force=true)
    end
end

# REVIEW: Only needed until something like <https://github.com/JuliaLang/julia/pull/55163> lands.
"""
    quicksleep(period::Real)

Sleep for `period` seconds, but use a busy loop for short periods (< 2ms).
"""
function quicksleep(period::Real)
    if period < 0.02
        start = time()
        while time() - start <= period
            yield()
        end
    else
        sleep(period)
    end
end
