function load(loader::DataLoader{:png}, from::IO, ::Type{Matrix})
    @import PNGFiles
    kwargs = (gamma = @getparam(loader."gamma"::Union{Nothing, Float64}),
              expand_paletted = @getparam(loader."expand_paletted"::Bool, false))
    # TODO support `background`
    PNGFiles.load(from; kwargs...)
end

function save(writer::DataWriter{:png}, dest::IO, info::Matrix)
    @import PNGFiles
    compression_strategy = let strat =
        @getparam(writer."compression_strategy"::Union{Int, String}, 3)
        if strat isa Int && 0 <= strat <= 4
            strat
        elseif strat ∈ ("default", "filtered", "huffmann", "rle", "fixed")
            findfirst(strat .== ("default", "filtered", "huffmann", "rle", "fixed"))::Int
        else
            @warn "Unrecognised PNG `compression_strategy` $(sprint(show, strat)), defaulting to 3"
            3
        end
    end
    filters = let filt = @getparam(writer."filters"::Union)
        if filt isa Int && 0 <= filt <= 4
            filt
        elseif strat ∈ ("none", "sub", "up", "average", "paeth")
            findfirst(strat .== ("none", "sub", "up", "average", "paeth"))::Int
        else
            @warn "Unrecognised PNG `filters` $(sprint(show, filt)), defaulting to 4"
            4
        end
    end
    kwargs = (; compression_level = @getparam(writer."compression_level"::Int, 0),
              compression_strategy, filters,
              gamma = @getparam(writer."gamma"::Union{Real, Nothing}))
    # TODO support `background`
    PNGFiles.save(dest, info; kwargs...)
end

create(::Type{DataLoader{:png}}, source::String) =
    !isnothing(match(r"\.png$"i, source))

create(::Type{DataWriter{:png}}, source::String) =
    !isnothing(match(r"\.png$"i, source))

const PNG_DOC = md"""
Encode and decode PNG images

# Input/output

The `png` driver expects data to be provided via `IO`.

It will parse to a `Matrix{<:Colorant}`.

# Required packages

- `PNGFile`

# Parameters

## Reader

- `gamma`: The gamma correction coefficient.
- `expand_paletted`: See the PNGFile docs.

## Writer

- `gamma`: The gamma correction coefficient.
- `compression_level`: 0-9
- `compression_strategy`: Either the number or string of: 0/"default",
  1/"filtered", 2/"huffman", 3/"rle" (default), or 4/"fixed".
- `filters`: Either the number or string of: 0/"none", 1/"sub", 3/"average",
  4/"paeth" (default)

# Usage examples

```toml
[[someimage.loader]]
driver = "png"
```
"""
