# Utility functions that don't belong to any particular file

"""
    natkeygen(key::String)

Generate a sorting key for `key` that when used with `sort` will put the
collection in "natural order".

```julia-repl
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
    while start < min(length(a), length(b))
        if a[start+1] == b[start+1]
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
