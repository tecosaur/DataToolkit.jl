module LockFiles

# If we only had to worry about Linux, a shared mutex would be the most
# appropriate way to implement cross-process locking. However, libuv does not
# have cross-platform versions of that part of libpthread, so instead we will
# resort to an over-engineered lock file with a PID queue and advisory locking
# (on Unix-like systems).

using BaseDirs

export LockFile, iscontested, adopt!

"""
    LockFile(parent, [prefix::AbstractString], target) -> LockFile

A per-user re-entrant FIFO lock file for arbitrary resources.

A `LockFile` can be used to synchronise access to a resource across multiple
processes. The lock is implemented by creating a file under the users runtime
directory with a name in the form `prefix-<hash of target>.lock`.

This requires the only relevant lock contention to be between processes owned by
the same user, and that `target` has the same `hash` across processes expected
to compete for the lock. Special care is taken to make sure that string targets
hash to the same value across Julia versions

Lock files are also scoped to a particular parent, which can be a `String` key,
a `BaseDirs.App`, or a `Module`. This allows for lock files to be used in a
project-specific manner, preventing name clashes between different projects or
modules.

Lock contentions are resolved in the order in which processes attempt to acquire
the lock (FIFO).
"""
mutable struct LockFile <: Base.AbstractLock
    const path::String
    file::Base.Filesystem.File
    const pid::Int32
    # `cond` guards `owner`/`depth`; the file protocol runs outside it.
    const cond::Threads.Condition
    owner::Union{Nothing, Task}
    depth::UInt32
    pidtop::Bool
    advlock::Bool
    mtime::Float64
end

"""
    LIVE_LOCKS::@NamedTuple{lock::ReentrantLock, entries::Vector{WeakRef}}

A collection of weak references to all currently live `LockFile` instances.
This is used to clean up lock files when the process exits.

The vector of references, `LIVE_LOCKS.entries`, can be accessed in a thread-safe
manner by locking `LIVE_LOCKS.lock` before accessing it. This is necessary to
ensure that the vector is not modified while it is being accessed.

While theoretically a `Set{WeakRef}` might be more appropriate,
we expect the number of live locks to remain small enough that the
asymptotic complexity difference does not become relevant.
"""
const LIVE_LOCKS = (lock = ReentrantLock(), entries = Vector{WeakRef}())

"""
    LOCKFILE_CHECK_EXPIRY::Float64

When considering whether a lock is still valid, we assume that
none of the processes that previously held the lock have died
within the last `LOCKFILE_CHECK_EXPIRY` seconds.

This reduces the frequency with which we query the state of the processes that
held the lock while the lock file is unchanged.
"""
const LOCKFILE_CHECK_EXPIRY = 1.0 # seconds

"""
    LOCKFILE_GRACE_PERIOD::Float64

When a lock has just been released, we will give processes which
requested access to the lock a grace period of `LOCKFILE_GRACE_PERIOD`
to acquire the lock before we grab it ourselves.

This value should be substantially larger than `LOCKFILE_MAX_CHECK_PERIOD`.
"""
const LOCKFILE_GRACE_PERIOD = 0.4 # seconds

"""
    LOCKFILE_MAX_CHECK_PERIOD::Float64

When trying to acquire a lock, we will wait at most `LOCKFILE_MAX_CHECK_PERIOD`
seconds before checking again if the lock is available.

This value should be substantially smaller than `LOCKFILE_GRACE_PERIOD`.
"""
const LOCKFILE_MAX_CHECK_PERIOD = 0.05 # seconds

const LOCKFILE_OPEN_FLAGS = Base.Filesystem.JL_O_CLOEXEC |
    Base.Filesystem.JL_O_CREAT | Base.Filesystem.JL_O_RDWR |
    Base.Filesystem.JL_O_DSYNC

const LOCKFILE_OPEN_MODE = Base.Filesystem.S_IRUSR | Base.Filesystem.S_IWUSR |
    Base.Filesystem.S_IRGRP | Base.Filesystem.S_IWGRP |
    Base.Filesystem.S_IROTH

"""
    flock(file::Base.Filesystem.File, exclusive::Bool=false)

Acquire an advisory lock on the file descriptor `fd`. If `exclusive` is `true`,
an exclusive lock is acquired, otherwise a shared lock is acquired. The lock is
released when the file descriptor is closed or when `funlock` is called.

!!! warning "Unix only"
    This only works on Unix-like systems.
"""
function flock end

"""
    funlock(file::Base.Filesystem.File)

Release any advisory locks created by `flock` for the file descriptor `fd`.

!!! warning "Unix only"
    This only works on Unix-like systems.
"""
function funlock end

@static if Sys.isunix()
    const LOCK_SH, LOCK_EX, LOCK_UN = Cint(1), Cint(2), Cint(8)

    function flock(file::Base.Filesystem.File, exclusive::Bool = false)
        lock = ifelse(exclusive, LOCK_EX, LOCK_SH)
        err = @ccall flock(RawFD(fd(file))::RawFD, lock::Cint)::Cint
        Base.systemerror("flock", err != 0)
        nothing
    end

    function funlock(file::Base.Filesystem.File)
        err = @ccall flock(RawFD(fd(file))::RawFD, LOCK_UN::Cint)::Cint
        Base.systemerror("flock", err != 0)
        nothing
    end
else
    flock(::RawFD, ::Bool=false) = nothing
    funlock(::RawFD) = nothing
end

function flock(lf::LockFile, exclusive::Bool=false)
    flock(lf.file, exclusive)
    lf.advlock = true
    nothing
end

function funlock(lf::LockFile)
    funlock(lf.file)
    lf.advlock = false
    nothing
end

"""
    cleanupfile(lf::LockFile, deref::Bool=true)

Close the file descriptor of the lock file `lf` and remove the file
if no other processes are currently holding the lock.

If `deref` is `true`, the lock file will also be removed from
the `LIVE_LOCKS.entries` vector, which is used to track all live lock files.
"""
function cleanupfile(lf::LockFile, deref::Bool=true)
    if isopen(lf.file)
        flock(lf, true)
        if all(p -> p <= 0 || !pidlive(p), pidqueue(lf))
            rm(lf.path, force=true)
        end
        funlock(lf)
        close(lf.file)
    end
    deref || return
    @lock LIVE_LOCKS.lock begin
        i = firstindex(LIVE_LOCKS.entries)
        while i <= lastindex(LIVE_LOCKS.entries)
            wr = LIVE_LOCKS.entries[i]
            if isnothing(wr.value) || wr.value === lf
                deleteat!(LIVE_LOCKS.entries, i)
            else
                i += 1
            end
        end
    end
end

function LockFile(path::String)
    ispath(dirname(path)) || mkpath(dirname(path))
    file = Base.Filesystem.open(path, LOCKFILE_OPEN_FLAGS, LOCKFILE_OPEN_MODE)
    lf = LockFile(path, file, getpid(), Threads.Condition(), nothing, zero(UInt32), false, false, zero(Float64))
    @lock LIVE_LOCKS.lock push!(LIVE_LOCKS.entries, WeakRef(lf))
    finalizer(cleanupfile, lf)
    lf
end

function LockFile(parent::Union{String, BaseDirs.App, Module}, prefix::AbstractString, target::UInt64)
    # It's well worth using the `runtime` dir for a lockfile, as beyond it being
    # appropriate on Linux it's usually a tempfs volume. This means it's an in-memory
    # filesystem, ~halving the time that `unlock(lock(::LockFile))` takes (10μs → 5μs)
    # and eliminating the risk of running into any filesystem synchronisation issues.
    path = BaseDirs.User.runtime(parent, prefix * "-" * string(target, base=32) * ".lock")
    LockFile(path)
end

LockFile(parent::Union{String, BaseDirs.App, Module}, prefix::String, target::AbstractString) =
    LockFile(parent, prefix, simplehash(target))

LockFile(parent::Union{String, BaseDirs.App, Module}, prefix::AbstractString, target) =
    LockFile(parent, prefix, hash(target))

LockFile(parent::Union{String, BaseDirs.App, Module}, target) = LockFile(parent, "", target)

"""
    simplehash(text::String) -> UInt64

Perform the (FNV-1a hash)[https://en.wikipedia.org/wiki/Fowler–Noll–Vo_hash_function] on the string `text`.

We must roll our own hash function to protect against changes to the hash
function across Julia versions.

The FNV-1a hash was chosen for its simplicity and low collision rate. It is not
intended to be cryptographically secure, but is it is at least not trivially
susceptible to pre-image attacks. Python used FNV-1a as its string/bytes hash
function until Python 3.4, with the main concern (hash flooding attacks)
relating to hash tables — not something we need to worry about here.
"""
function simplehash(text::String)
    h = 0xcbf29ce484222325
    for b in codeunits(text)
        h = (h ⊻ b) * 0x00000100000001B3
    end
    h
end

function Base.islocked(lf::LockFile)
    !isnothing(@lock lf.cond lf.owner) && return true
    lfstat = statopen!(lf)
    haslock = lf.advlock
    if mtime(lfstat) == lf.mtime && (time() - lf.mtime) < LOCKFILE_CHECK_EXPIRY
        return !lf.pidtop
    end
    if !haslock
        flock(lf)
        # Consider the edge-case where the lock file was
        # deleted between the `stat` and `flock` calls.
        lfstat = statopen!(lf)
    end
    # Actually check the lock file
    pidtop = pidsabove(lf) == 0
    !haslock && funlock(lf)
    lf.mtime = mtime(lfstat)
    lf.pidtop = pidtop
    !pidtop
end

"""
    pidlive(pid::Integer) -> Bool

Check whether the process with the given `pid` is still alive.

If a permission error occurs when trying to check the process, it is assumed
that the process is still alive.
"""
function pidlive(pid::Integer)
    iszero(@ccall uv_kill(pid::Cint, 0::Cint)::Cint) ||
        Base.Libc.errno() == Base.Libc.EPERM
end

"""
    pidqueue(lf::LockFile) -> Vector{Int32}

Return the PIDs of processes that have expressed interest in the lock file `lf`.

!!! warning
    Take care to ensure that `lf` is not modified during the this
    function call, for instance by taking an `flock` around it.
"""
function pidqueue(lf::LockFile)
    nbytes = filesize(lf.file)
    if nbytes == 0
        return Int32[]
    elseif nbytes % sizeof(Int32) != 0
        # We know this file is non-empty since we already checked `iszero(filesize(lfstat))`.
        keeplocked = lf.advlock
        flock(lf, true)
        nbytes = filesize(lf.file)
        if nbytes % sizeof(Int32) != 0
            # The file is corrupt, so we truncate it.
            truncate(lf.file, 0)
            funlock(lf)
            return Int32[]
        else # It got better?
            !keeplocked && funlock(lf)
        end
    end
    pids = Vector{Int32}(undef, nbytes ÷ 4)
    seekstart(lf.file)
    GC.@preserve pids unsafe_read(
        lf.file, Ptr{UInt8}(pointer(pids)), nbytes)
    pids
end

"""
    pidsabove(lf::LockFile) -> Int

Return the number of higher-priority PIDs in the lock file `lf`.
"""
function pidsabove(lf::LockFile)
    pids = pidqueue(lf)
    pidcount = 0
    for pid in pids
        if pid <= 0
            continue
        elseif pid == lf.pid
            break
        elseif pidlive(pid)
            pidcount += 1
        end
    end
    pidcount
end

"""
    iscontested(lf::LockFile) -> Bool

Indicate whether any other processes want to acquire `lf`.
"""
function iscontested(lf::LockFile)
    pidseen = 0
    for pid in pidqueue(lf)
        if pid > 0
            pidseen += 1
        end
        pidseen > 1 && return true
    end
    false
end

function acquire_inproc!(lf::LockFile; block::Bool)
    ct = current_task()
    @lock lf.cond begin
        while !(isnothing(lf.owner) || lf.owner === ct)
            block || return false
            wait(lf.cond)
        end
        lf.owner = ct
        lf.depth += 0x1
        true
    end
end

function release_inproc!(lf::LockFile)
    @lock lf.cond begin
        lf.depth -= 0x1
        iszero(lf.depth) || return
        lf.owner = nothing
        notify(lf.cond, all=false)
    end
    nothing
end

function Base.trylock(lf::LockFile)
    acquire_inproc!(lf, block=false) || return false
    lf.depth > 0x1 && return true
    try
        claim_pidfront!(lf) && return true
    catch
        release_inproc!(lf)
        rethrow()
    end
    release_inproc!(lf)
    false
end

function claim_pidfront!(lf::LockFile)
    statopen!(lf)
    flock(lf, true)
    try
        rawpids = pidqueue(lf)
        livepids = filter(p -> p > 0 && pidlive(p), rawpids)
        (isempty(livepids) || first(livepids) == lf.pid) || return false
        isempty(livepids) && push!(livepids, lf.pid)
        # Persist unless the file already leads with our live PID; an all-dead
        # queue must still be rewritten, else two processes prune the same corpse.
        if livepids != rawpids
            overwrite(lf, livepids)
            truncate(lf.file, sizeof(Int32) * length(livepids))
        end
        true
    finally
        funlock(lf)
    end
end

function Base.lock(lf::LockFile)
    acquire_inproc!(lf, block=true)
    lf.depth > 0x1 && return
    backoff = 0.00001 # 10μs, given that it takes 5μs lock + unlock on my machine
    try
        claim_pidfront!(lf) && return
        expressinterest(lf)
        while !claim_pidfront!(lf)
            GC.safepoint()
            quicksleep(backoff)
            backoff = min(LOCKFILE_MAX_CHECK_PERIOD, backoff * 2)
        end
    catch
        unclaim(lf)
        release_inproc!(lf)
        rethrow()
    end
end

function Base.unlock(lf::LockFile)
    final = @lock lf.cond begin
        isnothing(lf.owner) && throw(ConcurrencyViolationError("unlock of a LockFile that is not locked"))
        lf.owner === current_task() ||
            throw(ConcurrencyViolationError("unlock of a LockFile held by another task; `adopt!` it first"))
        lf.depth == 0x1
    end
    try
        final && unclaim(lf)
    finally
        release_inproc!(lf)
    end
    nothing
end

"""
    adopt!(lf::LockFile, old::Task)

Transfer ownership of `lf` from `old` to the current task.

This lets a critical section span tasks: the task that acquired `lf` names
itself as `old`, and the task that will release it adopts ownership first. Errors
if `lf` is not currently owned by `old`.
"""
function adopt!(lf::LockFile, old::Task)
    @lock lf.cond begin
        lf.owner === old ||
            throw(ConcurrencyViolationError("adopt! of a LockFile not owned by the given task"))
        lf.owner = current_task()
    end
    nothing
end

"""
    unclaim(lf::LockFile)

Remove our claim on the lock file `lf`, if it exists. This is used to
remove our PID from the lock file, which is necessary when we no longer
hold the lock but still have a PID entry in the lock file.

See also: `expressinterest`.
"""
function unclaim(lf::LockFile)
    isopen(lf.file) || return
    lfstat = stat(lf.file)
    (iszero(lfstat.nlink) || iszero(filesize(lfstat))) && return
    flock(lf, true)
    pids = pidqueue(lf)
    if length(pids) == 1 && first(pids) == lf.pid
        Base.Filesystem.truncate(lf.file, 0)
    else
        for (i, pid) in enumerate(pids)
            if pid == lf.pid
                pids[i] = -1 # Revoke our claim
            end
        end
        overwrite(lf, pids)
    end
    funlock(lf)
end

"""
    overwrite(lf::LockFile, nums::DenseVector{<:Integer})

Replace the contents of `lf` with `nums`.

If `nums` takes up less space than the existing contents of `lf`,
`truncate` should be called on `lf.file` (not taken care of here).
"""
function overwrite(lf::LockFile, nums::DenseVector{<:Integer})
    # I would have thought seeking wouldn't be needed given the provided
    # write arg `offset=0`, however it seems that can produce appends and
    # so break the system, so we must seek first.
    seek(lf.file, 0)
    GC.@preserve nums unsafe_write(
        lf.file, Ptr{UInt8}(pointer(nums)), sizeof(eltype(nums)) * length(nums) % UInt, 0)
end

"""
    expressinterest(lf::LockFile)

Make an expression of interest in locking `lf`.

This will add the current process's PID to the lock file, putting it
in the queue of processes that are interested in acquiring the lock.

If the lock file is empty, it will be created with the current PID as
the first entry. If the lock file already contains the current PID,
it will do nothing.

See also: `unclaim`.
"""
function expressinterest(lf::LockFile)
    statopen!(lf)
    flock(lf, true)
    pids = pidqueue(lf)
    if lf.pid in pids # Already expressed interest
        funlock(lf)
        return
    end
    push!(pids, lf.pid)
    overwrite(lf, pids)
    funlock(lf)
end

function statopen!(lf::LockFile)
    function reopen!(lf::LockFile)
        dir = dirname(lf.path)
        isdir(dir) || mkpath(dir)
        lf.file = Base.Filesystem.open(lf.path, LOCKFILE_OPEN_FLAGS, LOCKFILE_OPEN_MODE)
        lf.advlock = false
        lf.mtime = 0.0
        lf.pidtop = false
        stat(lf.file)
    end
    !isopen(lf.file) && return reopen!(lf)
    lfstat = stat(lf.file)
    iszero(lfstat.nlink) && return reopen!(lf)
    lfstat
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

function __init__()
    atexit() do
        @lock LIVE_LOCKS.lock begin
            for wr in LIVE_LOCKS.entries
                isnothing(wr.value) && continue
                cleanupfile(wr.value::LockFile, false)
            end
        end
    end
end

end
