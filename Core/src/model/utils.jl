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
