# Serialisation/deserialisation

using Base.Threads # For the hashing

const MerkleNode = @NamedTuple{indent::Int64, kind::Symbol, checksum::Checksum, mtime::Float64, path::String}

"""
    read_merkles(io::IO) -> Vector{MerkleTree}

Read all `MerkleTree` representations contained in `io`.
"""
function read_merkles(io::IO)
    merkles = MerkleTree[]
    buf = IOBuffer()
    node = nothing
    while !eof(io)
        while isnothing(node) && !eof(io)
            node = try_read_merkle_line(io, buf)
        end
        tree, node = read_tree(io, buf, 0, node)
        isnothing(tree) || push!(merkles, tree)
    end
    merkles
end

"""
    write_merkle(dest::IO, node::MerkleTree, indent::Int = 0)

Write the merkle tree `node` to `dest`, with an initial indent of `indent`.
"""
function write_merkle(dest::IO, node::MerkleTree, indent::Int = 0)
    print(dest, ' '^indent, ifelse(isnothing(node.children), 'f', 'd'),
            ' ', string(reinterpret(UInt64, node.mtime), base=36),
            ' ', string(node.checksum),
            ' ', escape_newlines(node.path), '\n')
    if !isnothing(node.children)
        for child in node.children
            write_merkle(dest, child, indent + 2)
        end
    end
end

"""
    write_merkle([dest::IO], cm::CachedMerkles)

Write all Merkle trees contained in `cm` to `dest`, defaulting to its file.
"""
function write_merkle(dest::IO, cm::CachedMerkles)
    print(dest, "# Cache of directory Merkle Trees\n")
    for mt in cm.merkles
        print(dest, '\n')
        write_merkle(dest, mt)
    end
end

function write_merkle(cm::CachedMerkles)
    dir = dirname(cm.file.path)
    isdir(dir) || mkpath(dir)
    tempfile = cm.file.path * ".new"
    open(Base.Fix2(write_merkle, cm), tempfile, "w")
    mv(tempfile, cm.file.path; force=true)
    cm.file.mtime = mtime(cm.file.path)
end

function Base.get(mt::MerkleTree, path::AbstractString, default)
    pathcomponents = splitpath(path)
    for component in splitpath(mt.path)
        isempty(pathcomponents) && return default
        popfirst!(pathcomponents) == component || return default
    end
    (isnothing(mt.children) || isempty(mt.children)) && return mt
    mtchildren::Vector{MerkleTree} = mt.children # help the compiler
    for component in pathcomponents
        found = false
        for subtree in mtchildren
            if subtree.path == component
                mt = subtree
                found = true
            end
        end
        found || return default
    end
    mt
end

function Base.get(mt::MerkleTree, checksum::Checksum, default)
    mt.checksum == checksum && return mt
    if !isnothing(mt.children)
        for child in mt.children
            res = get(child, checksum, nothing)
            isnothing(res) || return res
        end
    end
    default
end

function Base.get(cm::CachedMerkles, checksum::Checksum, default)
    for mt in cm.merkles
        entry = get(mt, checksum, nothing)
        isnothing(entry) || return entry
    end
    default
end

function Base.length(mt::MerkleTree)
    if isnothing(mt.children)
        1
    else
        sum(length, mt.children, init=0) + 1
    end
end

# Calculating Merkle trees
#
# A persistent pool of `nthreads()` work-stealing workers takes one directory per
# work item. Against a prior tree, unchanged files/subtrees are reused; a fresh
# build is the same algorithm run against no prior tree.

using Mmap

# Files up to this size use a reused per-worker buffer; larger files are mmap'd.
const MERKLE_BUFFER_MAX = 64 * 1024 * 1024

# A reserved checksum for entries that could not be read or hashed. Distinct from
# any real digest (no algorithm is named `:inaccessible`) and stable across runs,
# so an entry becoming (in)accessible folds into its parent as a detected change
# rather than silently vanishing from the tree.
const MERKLE_INACCESSIBLE = Checksum(:inaccessible, UInt8[])

inaccessible_node(name::String, mtime::Float64 = 0.0) =
    MerkleTree(name, mtime, MERKLE_INACCESSIBLE, nothing)

# A directory awaiting its children; folded once `remaining` reaches zero.
mutable struct DirFrame
    const name::String
    const mtime::Float64
    const results::Vector{Union{Nothing, MerkleTree}}
    @atomic remaining::Int
    @atomic changed::Bool
    const original::Union{Nothing, MerkleTree}
    const parent::Union{DirFrame, Nothing}
    const index::Int
end

struct MerkleTask
    root::String
    path::String
    original::Union{Nothing, MerkleTree}
    parent::Union{DirFrame, Nothing}
    index::Int
end

struct MerklePool{F}
    deques::Vector{Vector{MerkleTask}}
    locks::Vector{SpinLock}
    checksum_fn::F
    outstanding::Atomic{Int}
    root_result::Base.RefValue{Union{Nothing, MerkleTree}}
end

function MerklePool(n::Int, checksum_fn::F) where {F}
    MerklePool{F}([MerkleTask[] for _ in 1:n], [SpinLock() for _ in 1:n],
                  checksum_fn, Atomic{Int}(0), Ref{Union{Nothing, MerkleTree}}(nothing))
end

function submit!(pool::MerklePool, wid::Int, task::MerkleTask)
    atomic_add!(pool.outstanding, 1)
    @lock pool.locks[wid] push!(pool.deques[wid], task)
end

function take_or_steal!(pool::MerklePool, wid::Int)
    own = @lock pool.locks[wid] if !isempty(pool.deques[wid]) pop!(pool.deques[wid]) end
    isnothing(own) || return own
    for j in eachindex(pool.deques)
        j == wid && continue
        stolen = @lock pool.locks[j] if !isempty(pool.deques[j]) popfirst!(pool.deques[j]) end
        isnothing(stolen) || return stolen
    end
    nothing
end

function report!(pool::MerklePool, parent::Union{DirFrame, Nothing},
                 index::Int, node::Union{Nothing, MerkleTree}, changed::Bool)
    if isnothing(parent)
        pool.root_result[] = node
        return
    end
    parent.results[index] = node
    changed && (@atomic parent.changed = true)
    if (@atomic parent.remaining -= 1) == 0
        folded, fchanged = fold_dir(pool.checksum_fn, parent)
        report!(pool, parent.parent, parent.index, folded, fchanged)
    end
end

function fold_dir(checksum_fn::F, frame::DirFrame) where {F}
    children = MerkleTree[child for child in frame.results if !isnothing(child)]
    orig = frame.original
    if !isnothing(orig) && orig.path == frame.name && !(@atomic frame.changed) &&
        !isnothing(orig.children) && length(orig.children) == length(children)
        return orig, false
    end
    # The node's own name is excluded from its digest, so checksums relocate
    digest = IOBuffer()
    for child in children
        write(digest, child.path, child.checksum.hash)
    end
    checksum = try checksum_fn(seekstart(digest)) catch; MERKLE_INACCESSIBLE end
    MerkleTree(frame.name, frame.mtime, checksum, children), true
end

function hash_file(checksum_fn::F, fullpath::String, buf::Vector{UInt8}) where {F}
    sz = filesize(fullpath)
    if sz > MERKLE_BUFFER_MAX
        mapped = Mmap.mmap(fullpath)
        try
            checksum_fn(IOBuffer(mapped))
        finally
            finalize(mapped)
        end
    else
        resize!(buf, sz)
        read!(fullpath, buf)
        checksum_fn(IOBuffer(buf))
    end
end

function match_original(original::Union{Nothing, MerkleTree}, child::String, childstat)
    isnothing(original) && return nothing
    isnothing(original.children) && return nothing
    for oc in original.children
        oc.path == child && return oc
    end
    if isdir(childstat)
        for oc in original.children
            oc.mtime == mtime(childstat) && !isnothing(oc.children) && return oc
        end
    end
    nothing
end

function process_dir!(pool::MerklePool, wid::Int, task::MerkleTask, buf::Vector{UInt8})
    isfile_unchanged(ochild::MerkleTree, estat) =
        isnothing(ochild.children) && !islink(estat) && isfile(estat) && ochild.mtime == mtime(estat)
    checksum_fn = pool.checksum_fn
    fullpath = joinpath(task.root, task.path)
    dstat, entries = try (stat(fullpath), readdir(fullpath)) catch
        report!(pool, task.parent, task.index, inaccessible_node(task.path), true)
        return
    end
    orig = task.original
    if isempty(entries)
        node = MerkleTree(task.path, mtime(dstat), checksum_fn(IOBuffer(UInt8[])), MerkleTree[])
        changed = isnothing(orig) || orig.checksum != node.checksum
        report!(pool, task.parent, task.index, if changed node else orig end, changed)
        return
    end
    # A directory whose child set shrank counts as changed even if survivors match.
    prechanged = !isnothing(orig) && !isnothing(orig.children) && length(orig.children) != length(entries)
    frame = DirFrame(task.path, mtime(dstat),
                     Vector{Union{Nothing, MerkleTree}}(nothing, length(entries)),
                     length(entries), prechanged, orig, task.parent, task.index)
    for (i, entry) in enumerate(entries)
        childpath = joinpath(fullpath, entry)
        try
            estat = lstat(childpath)
            ochild = match_original(orig, entry, estat)
            if isdir(estat) && !islink(estat)
                submit!(pool, wid, MerkleTask(fullpath, entry, ochild, frame, i))  # reports later
            elseif !isnothing(ochild) && isfile_unchanged(ochild, estat)
                report!(pool, frame, i, ochild, false)  # unchanged file — no re-hash
            elseif islink(estat)
                report!(pool, frame, i, seq_merkle(checksum_fn, fullpath, entry, String[]), true)
            elseif isfile(estat) && isreadable(childpath)
                report!(pool, frame, i,
                        MerkleTree(entry, mtime(estat), hash_file(checksum_fn, childpath, buf), nothing), true)
            else
                report!(pool, frame, i, inaccessible_node(entry), true)
            end
        catch; report!(pool, frame, i, inaccessible_node(entry), true) end
    end
end

# Symlinked subtrees are resolved sequentially, with cycle detection via `descent`.
function seq_merkle(checksum_fn::F, root::String, path::String, descent::Vector{String}) where {F}
    fullpath = joinpath(root, path)
    pathstat = stat(fullpath)
    if !isreadable(fullpath)
        nothing
    elseif islink(lstat(fullpath))
        target = abspath(dirname(fullpath), readlink(fullpath))
        tindex = findfirst(==(target), descent)
        if !isnothing(tindex)
            cycle = IOBuffer()
            for i in tindex:length(descent)
                println(cycle, descent[i], UInt8(i - tindex))
            end
            return MerkleTree(path, mtime(pathstat), checksum_fn(seekstart(cycle)), MerkleTree[])
        end
        sub = seq_merkle(checksum_fn, "", target, vcat(descent, target))
        if !isnothing(sub) MerkleTree(path, sub.mtime, sub.checksum, sub.children) end
    elseif isfile(pathstat)
        MerkleTree(path, mtime(fullpath), open(checksum_fn, fullpath), nothing)
    elseif isdir(pathstat)
        children = MerkleTree[]
        digest = IOBuffer()
        for entry in readdir(fullpath)
            child = seq_merkle(checksum_fn, fullpath, entry, descent)
            isnothing(child) && continue
            push!(children, child)
            write(digest, child.path, child.checksum.hash)
        end
        MerkleTree(path, mtime(pathstat), checksum_fn(seekstart(digest)), children)
    end
end

function worker!(pool::MerklePool, wid::Int)
    buf = UInt8[]
    # Children are submitted before their parent is decremented, so `outstanding`
    # only hits zero once the whole tree is done.
    while pool.outstanding[] > 0
        task = take_or_steal!(pool, wid)
        if isnothing(task)
            yield()
            continue
        end
        try
            process_dir!(pool, wid, task, buf)
        catch
            # No worker throw may escape: a stranded task would leak its counter
            # decrement and spin the other workers forever. Record the subtree as
            # inaccessible and carry on.
            report!(pool, task.parent, task.index, inaccessible_node(task.path), true)
        finally
            atomic_sub!(pool.outstanding, 1)
        end
    end
end

"""
    merkle([cache::CachedMerkles], [original::MerkleTree], [root::String], path::String, algorithm::Symbol)

Create a `MerkleTree` of `path`, relative to `root`.

The tree is built in parallel across `nthreads()` workers. Given an `original`
tree (or a `cache`), unchanged files and subtrees — matched by name and mtime —
are reused without re-hashing. Any hashing `algorithm` recognised by `checksum`
may be used.

Returns `nothing` if the path cannot be resolved or checksummed.
"""
merkle(root::String, path::String, checksum_fn::F) where {F <: Function} =
    _merkle(root, path, checksum_fn, nothing)

merkle(original::MerkleTree, root::String, path::String, checksum_fn::F) where {F <: Function} =
    _merkle(root, path, checksum_fn, original)

function _merkle(root::String, path::String, checksum_fn::F,
                 original::Union{Nothing, MerkleTree}) where {F <: Function}
    root = String(rstrip(root, ('/', '\\')))
    path = String(rstrip(path, ('/', '\\')))
    fullpath = joinpath(root, path)
    st = stat(fullpath)
    isreadable(fullpath) || return nothing
    if !isdir(st) || islink(lstat(fullpath))
        return seq_merkle(checksum_fn, root, path, String[])  # single file / symlink root
    end
    pool = MerklePool(nthreads(), checksum_fn)
    submit!(pool, 1, MerkleTask(root, path, original, nothing, 0))
    tasks = [Threads.@spawn worker!(pool, w) for w in 1:nthreads()]
    foreach(wait, tasks)
    pool.root_result[]
end

function merkle(root::String, path::String, algorithm::Symbol = CHECKSUM_DEFAULT_SCHEME)
    fn = checksum(algorithm)
    if !isnothing(fn) merkle(root, path, fn) end
end

function merkle(original::MerkleTree, root::String, path::String,
                algorithm::Symbol = original.checksum.alg)
    if original.checksum.alg == algorithm
        fn = checksum(algorithm)
        if !isnothing(fn) merkle(original, root, path, fn) end
    else
        merkle(root, path, algorithm)
    end
end

merkle(original::MerkleTree, path::String, algorithm::Symbol) =
    merkle(original, "", path, algorithm)

# Cached layer: find the path in the cache, incrementally refresh, write back if changed.
function merkle(cm::CachedMerkles, root::String, path::String, algorithm::Symbol;
                last_checksum::Union{Checksum, Nothing} = nothing)
    refresh_cache!(cm)
    for (i, mt) in enumerate(cm.merkles)
        entry = get(mt, path, nothing)
        if isnothing(entry) && !isnothing(last_checksum)
            entry = get(mt, last_checksum, nothing)
        end
        isnothing(entry) && continue
        updated = @log_do("store:merkle:check", "Checking MerkleTree hash of $path",
                          merkle(entry, root, path))
        if updated !== entry
            if isnothing(updated)
                deleteat!(cm.merkles, i)
            else
                cm.merkles[i] = updated
            end
            write_merkle(cm)
        end
        return updated
    end
    entry = @log_do "store:merkle:create" "Creating MerkleTree hash of $path" merkle(root, path, algorithm)
    isnothing(entry) && return
    push!(cm.merkles, entry)
    write_merkle(cm)
    entry
end

function merkle(cm::CachedMerkles, path::String, algorithm::Symbol;
                last_checksum::Union{Checksum, Nothing} = nothing)
    cmdir = dirname(cm.file.path)
    if path == cmdir || startswith(path, joinpath(cmdir, ""))
        merkle(cm, cmdir, relpath(path, cmdir), algorithm; last_checksum)
    else
        merkle(cm, "", abspath(path), algorithm; last_checksum)
    end
end

function refresh_cache!(cm::CachedMerkles)
    cmtime = mtime(cm.file.path)
    if cmtime > cm.file.mtime
        empty!(cm.merkles)
        @log_do "store:merkle:read" "Reading MerkleTree cache" append!(cm.merkles, open(read_merkles, cm.file.path))
        cm.file.mtime = cmtime
    else
        cm
    end
end

# Helper functions

"""
    read_tree(io::IO, buf::IO, minimum_indent::Int, node) ->
        (Union{MerkleTree, Nothing}, Union{typeof(node), Nothing})

Read the `MerkleTree` that stems from `node`, if sensible.

The `node` argument must be a return value of `try_read_merkle_line`.
Reads from `io` are buffered by reuse of `buf`.

The return values consist of:
- The constructed `MerkleTree`, if sensible to do so (i.e. was preceded by
  an indent of at least `minimum_indent`).
- The next node not contained in the constructed `MerkleTree`, if applicable.
"""
function read_tree(io::IO, buf::IO, minimum_indent::Int, node::Union{MerkleNode, Nothing})
    if isnothing(node) || node.indent < minimum_indent
        nothing, node
    elseif node.kind == :file
        MerkleTree(node.path, node.mtime, node.checksum, nothing), nothing
    elseif node.kind == :dir
        children = Vector{MerkleTree}()
        while true
            seekstart(buf)
            child, next_node::Union{MerkleNode, Nothing} = read_tree(
                io, buf, node.indent + 1, try_read_merkle_line(io, buf))
            while !isnothing(next_node)
                isnothing(child) || push!(children, child)
                if next_node.indent <= minimum_indent + 1
                    return MerkleTree(node.path, node.mtime, node.checksum, children), next_node
                else
                    child, next_node = read_tree(io, buf, node.indent + 1, next_node)
                end
            end
            if child isa MerkleTree
                push!(children, child)
            elseif isnothing(child)
                return MerkleTree(node.path, node.mtime, node.checksum, children), next_node
            end
        end
        # Shouldn't ever hit this, but needed to make the return type stable.
        nothing, nothing
    end::Tuple{Union{MerkleTree, Nothing}, Union{MerkleNode, Nothing}}
end

"""
    try_read_merkle_line(io::IO, [buf::IO])

Read a single line from `io` representing an entry of a `MerkleTree`.

If this is not possible, for whatever reason, `nothing` is returned.
Optionally, reading can be buffered by providing `buf`.

The line should be of the format:

```text
<indent> <f or d> <mtime> <checksum> <path>
```

Here are some examples:

# Examples

```julia-repl
julia> try_read_merkle_line(IOBuffer("d 101t3scp5ey9w alg:1234 some/dir"))
(indent = 0, kind = :dir, checksum = Checksum(:alg, UInt8[0x12, 0x34]), mtime = 1.718190355243043e9, path = "some/dir")

julia> try_read_merkle_line(IOBuffer("  f 101t3scouw0l3 alg:2345 file"))
(indent = 2, kind = :file, checksum = Checksum(:alg, UInt8[0x23, 0x45]), mtime = 1.718190351027891e9, path = "file")
```
"""
function try_read_merkle_line(io::IO)
    eof(io) && return
    char1 = read(io, UInt8)
    indent = 0
    if char1 == UInt8('\n')
        return
    elseif char1 == UInt8('#')
        readuntil(io, UInt8('\n'))
        return
    end
    while char1 == UInt8(' ')
        indent += 1
        char1 = read(io, UInt8)
        eof(io) && return
    end
    kind = if char1 == UInt8('f')
        :file
    elseif char1 == UInt8('d')
        :dir
    else
        return
    end
    read(io, UInt8) == UInt8(' ') || return
    eof(io) && return
    mtime_u = tryparse(UInt64, readuntil(io, ' '), base=36)
    isnothing(mtime_u) && return
    mtime = reinterpret(Float64, mtime_u)
    checksum = tryparse(Checksum, readuntil(io, ' '))
    isnothing(checksum) && return
    eof(io) && return
    path = String(unescape_newlines!(readuntil(io, UInt8('\n'))))
    (; indent, kind, checksum, mtime, path)
end

function try_read_merkle_line(io::IO, buf::IO)
    eof(io) && return
    copyuntil(seekstart(buf), io, UInt8('\n'), keep=true) |>
        seekstart |> try_read_merkle_line
end

"""
    unescape_newlines!(content::Vector{UInt8}) -> content

Modify `content` in-place to replace escaped newlines with actual newlines.
"""
function unescape_newlines!(bytes::Vector{UInt8})
    if UInt8('\\') ∉ bytes
        bytes
    else
        i = firstindex(bytes)
        delinds = Int[]
        while i < length(bytes)
            if bytes[i] == UInt8('\\')
                if bytes[i + 1] == UInt8('n')
                    bytes[i] = UInt8('\n')
                    push!(delinds, i += 1)
                elseif bytes[i + 1] == UInt8('\\')
                    push!(delinds, i += 1)
                end
            end
            i += 1
        end
        deleteat!(bytes, delinds)
    end
    bytes
end

"""
    escape_newlines(content::AbstractVector{UInt8}) -> Vector{UInt8}
    escape_newlines(content::String) -> String

Replace newlines and backslashes in `content` with escaped versions.
"""
function escape_newlines(bytes::AbstractVector{UInt8})
    newbytes = UInt8[]
    sizehint!(newbytes, length(bytes) + count(==(UInt8('\n')), bytes))
    for b in bytes
        if b == UInt8('\n')
            push!(newbytes, UInt8('\\'), UInt8('n'))
        elseif b == UInt8('\\')
            push!(newbytes, UInt8('\\'), UInt8('\\'))
        else
            push!(newbytes, b)
        end
    end
    newbytes
end

function escape_newlines(s::String)
    if '\n' ∈ s
        String(escape_newlines(codeunits(s)))
    else s end
end
