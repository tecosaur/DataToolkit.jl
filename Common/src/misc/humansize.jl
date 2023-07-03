# Get then nice SI representation of a byte size. Useful in a few different places.

"""
    humansize(bytes::Integer; digits::Int=1)

Determine the SI prefix for `bytes`, then give a tuple of the number of bytes
with that prefix (rounded to `digits`), and the units as a string.

## Examples

```jldoctest; setup = :(import DataToolkitCommon.humansize)
julia> humansize(123)
(123, "B")

julia> humansize(1234)
(1.2, "KiB")

julia> humansize(1000^3)
(954, "MiB")

julia> humansize(1024^3)
(1.0, "GiB")
```
"""
function humansize(bytes::Integer; digits::Int=1)
    units = ("B", "KiB", "MiB", "GiB", "TiB", "PiB")
    magnitude = floor(Int, log(1024, 1 + bytes))
    if 10 < bytes < 10*1024^magnitude
        round(bytes / 1024^magnitude; digits)
    else
        round(Int, bytes / 1024^magnitude)
    end, units[1+magnitude]
end
