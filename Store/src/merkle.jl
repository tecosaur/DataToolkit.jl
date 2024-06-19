# Serialisation/deserialisation

using Base.Threads # For the hashing

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
    isempty(mt.children) && return mt
    for component in pathcomponents
        found = false
        for subtree in mt.children
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
    if mt.checksum == checksum
        mt
    elseif !isnothing(mt.children)
        for child in mt.children
            res = get(child, checksum, nothing)
            isnothing(res) || return res
        end
    else
        default
    end
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

# Actually calculating Merkle trees

"""
    merkle([cache], [root::String], path::String, algorithm::Symbol)

Relative to a certain `root` directory, create a `MerkleTree` of `path`.

If the path could not be resolved, or points to a special filesystem object,
`nothing` is returned.

The constructed `MerkleTree` can use any hashing `algorithm` recognised
by `checksum`.
"""
function merkle(root::String, path::String, algorithm::Symbol = CHECKSUM_DEFAULT_SCHEME)
    _merkle(String(rstrip(root, ('/', '\\'))), String(rstrip(path, ('/', '\\'))), algorithm, checksum(algorithm),
            (Dict{String, Union{MerkleTree, Nothing, ReentrantLock}}(), ReentrantLock()), String[])
end

merkle(path::String, algorithm::Symbol) = merkle("", path, algorithm)

"""
    _merkle(root::String, path::String, algorithm::Symbol, checksum_fn::F) where {F <: Function}

Internal function to create a Merkle tree for a `path` relative to a `root` directory.

The checksum function `checksum_fn` is used to calculate the checksums of files,
and should return `Checksum`s for the given `algorithm`.

Returns the constructed `MerkleTree` or `nothing` if the path does not exist,
or cannot be checksummed for some reason.
"""
function _merkle(root::String, path::String, algorithm::Symbol, checksum_fn::F,
                 (symlinks, symlinks_lock)::Tuple{Dict{String, Union{MerkleTree, Nothing, ReentrantLock}}, ReentrantLock},
                 symlink_descent::Vector{String}) where {F <: Function}
    fullpath = joinpath(root, path)
    pathstat = stat(fullpath)
    if !isreadable(fullpath)
        nothing
    elseif islink(lstat(fullpath))
        target = abspath(dirname(fullpath), readlink(fullpath))
        tindex = findfirst(==(target), symlink_descent)
        if !isnothing(tindex)
            cycle_io = IOBuffer()
            for i in tindex:length(symlink_descent)
                println(cycle_io, symlink_descent[i], UInt8(i - tindex))
            end
            return MerkleTree(path, mtime(pathstat), checksum_fn(seekstart(cycle_io)), MerkleTree[])
        end
        lock(symlinks_lock)
        if haskey(symlinks, target)
            mtree = symlinks[target]
            unlock(symlinks_lock)
            if mtree isa ReentrantLock
                @lock mtree symlinks[target]
            elseif mtree isa MerkleTree
                MerkleTree(path, mtree.mtime, mtree.checksum, mtree.children)
            end
        else
            mlock = ReentrantLock()
            lock(mlock)
            symlinks[target] = mlock
            unlock(symlinks_lock)
            mtree = _merkle("", target, algorithm, checksum_fn, (symlinks, symlinks_lock), vcat(symlink_descent, target))
            symlinks[target] = mtree
            unlock(mlock)
            if mtree isa MerkleTree
                MerkleTree(path, mtree.mtime, mtree.checksum, mtree.children)
            end
        end
    elseif isfile(pathstat)
        MerkleTree(path, mtime(fullpath), open(checksum_fn, fullpath), nothing)
    elseif isdir(pathstat)
        childnames = collect(enumerate(readdir(fullpath)))
        childtrees = Tuple{Int, MerkleTree}[]
        ctreelock = SpinLock()
        @threads for (i, child) in childnames
            ctree = _merkle(fullpath, child, algorithm, checksum_fn, (symlinks, symlinks_lock), symlink_descent)
            isnothing(ctree) || @lock ctreelock push!(childtrees, (i, ctree))
        end
        children = MerkleTree[]
        dirgestive = IOBuffer()
        write(dirgestive, path)
        for (_, ctree) in sort(childtrees, by=first)
            isnothing(ctree) && continue
            push!(children, ctree)
            write(dirgestive, ctree.path, ctree.checksum.hash)
        end
        MerkleTree(path, mtime(pathstat), checksum_fn(seekstart(dirgestive)), children)
    end
end

function merkle(original::MerkleTree, root::String, path::String, algorithm::Symbol = original.checksum.alg)
    if original.checksum.alg == algorithm
        _merkle(original, String(rstrip(root, ('/', '\\'))), String(rstrip(path, ('/', '\\'))),
                original.checksum.alg, checksum(original.checksum.alg),
                (Dict{String, Union{MerkleTree, Nothing, ReentrantLock}}(), ReentrantLock()), String[])
    else
        merkle(root, path, original.checksum.alg)
    end
end

merkle(original::MerkleTree, path::String, algorithm::Symbol) = merkle(original, "", path, algorithm)

function _merkle(original::MerkleTree, root::String, path::String, algorithm::Symbol, checksum_fn::F,
                 (symlinks, symlinks_lock)::Tuple{Dict{String, Union{MerkleTree, Nothing, ReentrantLock}}, ReentrantLock},
                 symlink_descent::Vector{String}) where {F <: Function}
    fullpath = joinpath(root, path)
    pathstat = stat(fullpath)
    if !isreadable(fullpath)
        nothing, true
    elseif isfile(pathstat)
        if original.path == path && original.mtime == mtime(pathstat)
            original, false
        else
            csum = open(checksum_fn, fullpath)
            # @warn "- changed: $fullpath"
            MerkleTree(path, mtime(fullpath), csum, nothing), true
        end
    elseif isdir(pathstat)
        childnames = collect(enumerate(readdir(fullpath)))
        childtrees = Tuple{Int, MerkleTree, Bool}[]
        ctreelock = SpinLock()
        @threads for (i, child) in childnames
            origchild = nothing
            for ochild in original.children
                if ochild.path == child
                    origchild = ochild
                    break
                end
            end
            if isnothing(origchild)
                for ochild in original.children
                    childstat = stat(joinpath(fullpath, child))
                    if ochild.mtime == mtime(childstat) && isdir(childstat)
                        origchild = ochild
                        break
                    end
                end
            end
            ctree, changed = if !isnothing(origchild)
                _merkle(origchild, fullpath, child, algorithm, checksum_fn, (symlinks, symlinks_lock), symlink_descent)
            else
                _merkle(fullpath, child, algorithm, checksum_fn, (symlinks, symlinks_lock), symlink_descent), true
            end
            isnothing(ctree) || @lock ctreelock push!(childtrees, (i, ctree, changed))
        end
        if original.path == path && length(original.children) == length(childtrees) && all(!last, childtrees)
            return original, false
        end
        children = MerkleTree[]
        dirgestive = IOBuffer()
        write(dirgestive, path)
        for (_, ctree, _) in sort(childtrees, by=first)
            isnothing(ctree) && continue
            push!(children, ctree)
            write(dirgestive, ctree.path, ctree.checksum.hash)
        end
        csum = checksum_fn(seekstart(dirgestive))
        MerkleTree(path, mtime(fullpath), csum, children), true
    else
        nothing, true
    end
end

function merkle(cm::CachedMerkles, root::String, path::String, algorithm::Symbol;
                last_checksum::Union{Checksum, Nothing} = nothing)
    refresh_cache!(cm)
    for (i, mt) in enumerate(cm.merkles)
        entry = get(mt, path, nothing)
        if isnothing(entry) && !isnothing(last_checksum)
            entry = get(mt, last_checksum, nothing)
        end
        isnothing(entry) && continue
        entry, updated = @log_do(
            "store:merkle:check",
            "Checking MerkleTree hash of $path",
            merkle(entry, root, path))
        if updated
            if isnothing(entry)
                deleteat!(cm.merkles, i)
            else
                cm.merkles[i] = entry
            end
            write_merkle(cm)
        end
        return entry
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
    if startswith(path, cmdir)
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
function read_tree(io::IO, buf::IO, minimum_indent::Int, node)
    if isnothing(node) || node.indent < minimum_indent
        nothing, node
    elseif node.kind == :file
        MerkleTree(node.path, node.mtime, node.checksum, nothing), nothing
    elseif node.kind == :dir
        children = Vector{MerkleTree}()
        while true
            seekstart(buf)
            child, next_node = read_tree(
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
    end
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
