# Utility functions that don't belong to any particular file

"""
    natkeygen(key::String)

Generate a sorting key for `key` that when used with `sort` will put the
collection in "natural order".

```jldoctest; setup = :(import DataToolkitBase.natkeygen)
julia> natkeygen.(["A1", "A10", "A02", "A1.5"])
4-element Vector{Vector{AbstractString}}:
 ["a", "0\x01"]
 ["a", "0\n"]
 ["a", "0\x02"]
 ["a", "0\x015"]

julia> sort(["A1", "A10", "A02", "A1.5"], by=natkeygen)
4-element Vector{String}:
 "A1"
 "A1.5"
 "A02"
 "A10"
```
"""
function natkeygen(key::String)
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
    stringdist(a::AbstractString, b::AbstractString)

Calculate the Restricted Damerau-Levenshtein distance (aka. Optimal String
Alignment) between `a` and `b`.

This is the minimum number of edits required to transform `a` to `b`, where each
edit is a *deletion*, *insertion*, *substitution*, or *transposition* of a
character, with the restriction that no substring is edited more than once.

# Examples

```jldoctest; setup = :(import DataToolkitBase.stringdist)
julia> stringdist("The quick brown fox jumps over the lazy dog",
                  "The quack borwn fox leaps ovver the lzy dog")
7

julia> stringdist("typo", "tpyo")
1

julia> DataToolkitBase.stringdist("frog", "cat")
4
```
"""
function stringdist(a::AbstractString, b::AbstractString)
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
    v₀ = collect(1:(length(b) - start))
    v₁ = similar(v₀)
    aᵢ₋₁, bⱼ₋₁ = first(a), first(b)
    current = 0
    for (i, aᵢ) in enumerate(a)
        i > start || (aᵢ₋₁ = aᵢ; continue)
        left = i - start - 1
        current = i - start
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
                # Minimum between substitution, deletion and insertion
                current = min(current + 1, above + 1, left + 1)
                if i > start + 1 && j > start + 1 && aᵢ == bⱼ₋₁ && aᵢ₋₁ == bⱼ
                    current = min(current, (this_transition += 1))
                end
            end
            v₀[j - start] = current
            bⱼ₋₁ = bⱼ
        end
        aᵢ₋₁ = aᵢ
    end
    current
end

"""
    stringsimilarity(a::AbstractString, b::AbstractString)

Return the `stringdist` as a proportion of the maximum length of `a` and `b`,
take one.

# Example

```jldoctest; setup = :(import DataToolkitBase.stringsimilarity)
julia> stringsimilarity("same", "same")
1.0

julia> stringsimilarity("semi", "demi")
0.75
```
"""
stringsimilarity(a::AbstractString, b::AbstractString) =
    1 - stringdist(a, b) / max(length(a), length(b))

"""
    longest_common_subsequence(a, b)

Find the longest common subsequence of `b` within `a`, returning the indicies of
`a` that comprise the subsequence.

This function is intended for strings, but will work for any indexable objects
with `==` equality defined for their elements.

# Example

```jldoctest; setup = :(import DataToolkitBase.longest_common_subsequence)
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
