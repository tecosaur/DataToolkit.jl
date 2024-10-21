# Utility functions that don't belong to any particular file
#
# Arguably some of these functions don't even belong to this package,
# but they aren't implemented anywhere else, so...

"""
    newdict(K::Type, V::Type, capacity::Int) -> Dict{K, V}

Create a new `Dict{K, V}` sized to hold `capacity` elements, hopefully without
resizing. Depending on the particular value of `capacity` and the Julia version,
this can result in substantial memory savings for small dictionaries.
"""
function newdict end

@static if VERSION >= v"1.11-alpha1"
    function newdict(K::Type, V::Type, capacity::Int)
        size = if capacity < 1; 0
        elseif capacity == 1; 2
        elseif capacity == 2; 3
        elseif 3 <= capacity <= 5; 8
        else cld(capacity * 3, 2) end
        slots = Memory{UInt8}(undef, size)
        fill!(slots, 0x00)
        Dict{K, V}(slots,
                   Memory{K}(undef, size),
                   Memory{V}(undef, size),
                   0, 0, zero(UInt), max(1, size), 0)
    end
else
    function newdict(K::Type, V::Type, capacity::Int)
        size = if capacity < 1; 1
        elseif capacity == 1; 2
        elseif 2 <= capacity <= 4; 8
        else cld(capacity * 3, 2) end
        slots = Vector{UInt8}(undef, size)
        fill!(slots, 0x00)
        Dict{K, V}(slots,
                   Vector{K}(undef, size),
                   Vector{V}(undef, size),
                   0, 0, zero(UInt), size, 0)
    end
end

"""
    shrinkdict(dict::Dict) -> Dict

If `dict` looks like it may be smaller if reconstructed using `newdict`, do so.
"""
function shrinkdict(dict::Dict{K, V}) where {K, V}
    if length(dict) <= 6
        dnew = newdict(K, V, length(dict))
        for (k, v) in dict
            dnew[k] = v
        end
        dnew
    else
        dict
    end
end

"""
    atomic_write(f::Function, dest::AbstractString; temp::AbstractString = dest * "_XXXX.part")

Atomically write to `dest` with `f`, via `temp`.

Calls the function `f` that writes to `temp`, with `temp` given as an `IO`
handle or a `String` depending on `as`. Upon completion, `temp` is renamed to
`dest`.

The file `dest` is not touched until the write is complete, and if the write to
`dest` is interrupted or fails for any reason, no data is written to `temp`.

!!! warning "Limitations"
     It is impossible to gauntree truly atomic writes on hardware without power loss
     protection (PLP), even with copy-on-write (CoW) filesystems. This function makes
     a best effort, calling
     [`fdatasync`](https://man7.org/linux/man-pages/man2/fdatasync.2.html)
     before renaming a file. In most situations this will be sufficient, but it
     is not a guarantee.
"""
function atomic_write end

function atomic_write(f::F, dest::AbstractString, temp::AbstractString) where {F <: Function}
    local ret
    try
        io = open(temp, "w")
        ret = f(io)
        flush(io)
        req = Libc.malloc(Base._sizeof_uv_fs)
        # REVIEW: When we drop 1.11 support `Base.RawFD(fd(io))` can be replaced with `fd(io)`
        @ccall uv_fs_fdatasync(C_NULL::Ptr{Cvoid}, req::Ptr{Cvoid}, Base.RawFD(fd(io))::Base.OS_HANDLE, C_NULL::Ptr{Cvoid})::Cint
        Libc.free(req)
        close(io)
    catch
        rm(temp, force=true)
        rethrow()
    end
    mv(temp, dest, force=true)
    ret
end

function atomic_write(f::F, dest::AbstractString) where {F <: Function}
    miliseconds = round(Int, 1000 * time()) % 1000 * 60 * 60 * 24
    suffix = string('-', string(miliseconds, base=36), ".part")
    atomic_write(f, dest, dest * suffix)
end

"""
    atomic_write(dest::AbstractString, content)

Atomically write `content` to `dest`, leaving no trace of incomplete/failed writes.
"""
atomic_write(dest::AbstractString, content) =
    atomic_write(Base.Fix2(write, content), dest)

"""
    natkeygen(key::String)

Generate a sorting key for `key` that when used with `sort` will put the
collection in "natural order".

```jldoctest; setup = :(import DataToolkitCore.natkeygen)
julia> natkeygen.(["A1", "A10", "A02", "A1.5"])
4-element Vector{Vector{String}}:
 ["a", "0\\x01"]
 ["a", "0\\n"]
 ["a", "0\\x02"]
 ["a", "0\\x015"]

julia> sort(["A1", "A10", "A02", "A1.5"], by=natkeygen)
4-element Vector{String}:
 "A1"
 "A1.5"
 "A02"
 "A10"
```
"""
function natkeygen(key::String)::Vector{String}
    map(eachmatch(r"(\d*\.\d+)|(\d+)|([^\d]+)", lowercase(key))) do (; captures)
        float, int, str = captures
        if !isnothing(float)
            f = parse(Float64, float)
            fint, dec = floor(Int, f), mod(f, 1)
            '0' * Char(fint) * string(dec)[3:end]
        elseif !isnothing(int)
            '0' * Char(parse(Int, int))
        else
            str
        end
    end
end

"""
    stringdist(a::AbstractString, b::AbstractString; halfcase::Bool=false)

Calculate the Restricted Damerau-Levenshtein distance (aka. Optimal String
Alignment) between `a` and `b`.

This is the minimum number of edits required to transform `a` to `b`, where each
edit is a *deletion*, *insertion*, *substitution*, or *transposition* of a
character, with the restriction that no substring is edited more than once.

When `halfcase` is true, substitutions that just switch the case of a character
cost half as much.

# Examples

```jldoctest; setup = :(import DataToolkitCore.stringdist)
julia> stringdist("The quick brown fox jumps over the lazy dog",
                  "The quack borwn fox leaps ovver the lzy dog")
7

julia> stringdist("typo", "tpyo")
1

julia> stringdist("frog", "cat")
4

julia> stringdist("Thing", "thing", halfcase=true)
0.5
```
"""
function stringdist(a::AbstractString, b::AbstractString; halfcase::Bool=false)
    if length(a) > length(b)
        a, b = b, a
    end
    start = 0
    for (i, j) in zip(eachindex(a), eachindex(b))
        if a[i] == b[j]
            start += 1
        else
            break
        end
    end
    start == length(a) && return length(b) - start
    v₀ = collect(2:2:2*(length(b) - start))
    v₁ = similar(v₀)
    aᵢ₋₁, bⱼ₋₁ = first(a), first(b)
    current = 0
    for (i, aᵢ) in enumerate(a)
        i > start || (aᵢ₋₁ = aᵢ; continue)
        left = 2*(i - start - 1)
        current = 2*(i - start)
        transition_next = 0
        @inbounds for (j, bⱼ) in enumerate(b)
            j > start || (bⱼ₋₁ = bⱼ; continue)
            # No need to look beyond window of lower right diagonal
            above = current
            this_transition = transition_next
            transition_next = v₁[j - start]
            v₁[j - start] = current = left
            left = v₀[j - start]
            if aᵢ != bⱼ
                # (Potentially) cheaper substitution when just
                # switching case.
                substitutecost = if halfcase
                    aᵢswitchcap = if isuppercase(aᵢ)
                        lowercase(aᵢ)
                    elseif islowercase(aᵢ)
                        uppercase(aᵢ)
                    else aᵢ end
                    ifelse(aᵢswitchcap == bⱼ, 1, 2)
                else
                    2
                end
                # Minimum between substitution, deletion and insertion
                current = min(current + substitutecost,
                              above + 2, left + 2) # deletion or insertion
                if i > start + 1 && j > start + 1 && aᵢ == bⱼ₋₁ && aᵢ₋₁ == bⱼ
                    current = min(current, (this_transition += 2))
                end
            end
            v₀[j - start] = current
            bⱼ₋₁ = bⱼ
        end
        aᵢ₋₁ = aᵢ
    end
    if halfcase current/2 else current÷2 end
end

"""
    stringsimilarity(a::AbstractString, b::AbstractString; halfcase::Bool=false)

Return the `stringdist` as a proportion of the maximum length of `a` and `b`,
take one. When `halfcase` is true, case switches cost half as much.

# Example

```jldoctest; setup = :(import DataToolkitCore.stringsimilarity)
julia> stringsimilarity("same", "same")
1.0

julia> stringsimilarity("semi", "demi")
0.75

julia> stringsimilarity("Same", "same", halfcase=true)
0.875
```
"""
stringsimilarity(a::AbstractString, b::AbstractString; halfcase::Bool=false) =
    1 - stringdist(a, b; halfcase) / max(length(a), length(b))

"""
    longest_common_subsequence(a, b)

Find the longest common subsequence of `b` within `a`, returning the indices of
`a` that comprise the subsequence.

This function is intended for strings, but will work for any indexable objects
with `==` equality defined for their elements.

# Example

```jldoctest; setup = :(import DataToolkitCore.longest_common_subsequence)
julia> longest_common_subsequence("same", "same")
4-element Vector{Int64}:
 1
 2
 3
 4

julia> longest_common_subsequence("fooandbar", "foobar")
6-element Vector{Int64}:
 1
 2
 3
 7
 8
 9
```
"""
function longest_common_subsequence(a, b)
    lengths = zeros(Int, length(a) + 1, length(b) + 1)
    for (i, x) in enumerate(a), (j, y) in enumerate(b)
        lengths[i+1, j+1] = if x == y
            lengths[i, j] + 1
        else
            max(lengths[i+1, j], lengths[i, j+1])
        end
    end
    subsequence = Int[]
    x, y = size(lengths)
    aind, bind = eachindex(a) |> collect, eachindex(b) |> collect
    while lengths[x,y] > 0
        if a[aind[x-1]] == b[bind[y-1]]
            push!(subsequence, x-1)
            x -=1; y -= 1
        elseif lengths[x, y-1] > lengths[x-1, y]
            y -= 1
        else
            x -= 1
        end
    end
    reverse(subsequence)
end

"""
    issubseq(a, b)

Return `true` if `a` is a subsequence of `b`, `false` otherwise.

## Examples

```jldoctest; setup = :(import DataToolkitCore.issubseq)
julia> issubseq("abc", "abc")
true

julia> issubseq("adg", "abcdefg")
true

julia> issubseq("gda", "abcdefg")
false
```
"""
issubseq(a, b) = length(longest_common_subsequence(a, b)) == length(a)

"""
    highlight_lcs(io::IO, a::String, b::String;
                  before::String="\\e[1m", after::String="\\e[22m",
                  invert::Bool=false)

Print `a`, highlighting the longest common subsequence between `a` and `b` by
inserting `before` prior to each subsequence region and `after` afterwards.

If `invert` is set, the `before`/`after` behaviour is switched.
"""
function highlight_lcs(io::IO, a::String, b::String;
                       before::String="\e[1m", after::String="\e[22m",
                       invert::Bool=false)
    seq = longest_common_subsequence(collect(a), collect(b))
    seq_pos = firstindex(seq)
    in_lcs = invert
    for (i, char) in enumerate(a)
        if seq_pos < length(seq) && seq[seq_pos] < i
            seq_pos += 1
        end
        if in_lcs != (i == seq[seq_pos])
            in_lcs = !in_lcs
            get(io, :color, false) && print(io, ifelse(in_lcs ⊻ invert, before, after))
        end
        print(io, char)
    end
    get(io, :color, false) && print(io, after)
end

"""
    multibar(io::IO, specs::Vector{<:Pair{Symbol, <:Real}}, width::Int=30)

Print a bar of certain `width` to `io`, split into segments according to `specs`.

Each element of `specs` is a pair `(color, weight)`, where `color` is
a named color recognised by `printstyled` and `weight` is a number.

Each segment is draw with a width proportional to its weight.

All segments with a non-zero weight are drawn.
"""
function multibar(io::IO, specs::Vector{<:Pair{Symbol, <:Real}}, width::Int=min(30, last(displaysize(io))))
    bars = (whole='━', lpart='╺', rpart='╸')
    specs = filter(s -> last(s) > 0, specs)
    isempty(specs) && return
    totalhalves = 2 * width - length(specs) + 1
    duowidth = totalhalves / sum(last, specs, init=0)
    halfwidths = [max(1, round(Int, weight * duowidth)) for (_, weight) in specs]
    widthdiff = sum(halfwidths) - totalhalves
    if widthdiff != 0
        rawproportions = map(last, specs) / sum(last, specs)
        stolenweights = ones(float(Int), length(halfwidths))
        while widthdiff != 0
            change = sign(widthdiff)
            i = argmax(rawproportions .* stolenweights)
            halfwidths[i] -= change
            stolenweights[i] = 1 - 1 / (1 + stolenweights[i])
            widthdiff -= change
        end
    end
    partial = false
    for ((color, _), halves) in zip(specs, halfwidths)
        partial && printstyled(io, bars.lpart; color)
        nbars = (halves - partial) ÷ 2
        partial = iszero(halves - partial - 2 * nbars)
        printstyled(io, bars.whole^nbars; color)
        !partial && printstyled(io, bars.rpart; color)
    end
end
