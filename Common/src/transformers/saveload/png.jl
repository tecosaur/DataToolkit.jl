function _read_png end # Implemented in `../../../ext/PNGFilesExt.jl`
function _write_png end # Implemented in `../../../ext/PNGFilesExt.jl`

function load(loader::DataLoader{:png}, from::IO, ::Type{Matrix})
    @require PNGFiles
    kwargs = (gamma = @getparam(loader."gamma"::Union{Nothing, Float64}),
              expand_paletted = @getparam(loader."expand_paletted"::Bool, false))
    # TODO support `background`
    invokelatest(_read_png, from; kwargs...)
end

function save(writer::DataWriter{:png}, dest::IO, info::Matrix)
    @require PNGFiles
    strategies = ("default", "filtered", "huffman", "rle", "fixed")
    compression_strategy = let strat =
        @getparam(writer."compression_strategy"::Union{Int, String}, 3)
        if strat isa Int && 0 <= strat <= 4
            strat
        elseif (i = findfirst(==(strat), strategies)) |> !isnothing
            i - 1
        else
            @warn "Unrecognised PNG `compression_strategy` $(sprint(show, strat)), defaulting to 3"
            3
        end
    end
    filternames = ("none", "sub", "up", "average", "paeth")
    filters = let filt = @getparam(writer."filters"::Union{Int, String}, 4)
        if filt isa Int && 0 <= filt <= 4
            filt
        elseif (i = findfirst(==(filt), filternames)) |> !isnothing
            i - 1
        else
            @warn "Unrecognised PNG `filters` $(sprint(show, filt)), defaulting to 4"
            4
        end
    end
    kwargs = (; compression_level = @getparam(writer."compression_level"::Int, 0),
              compression_strategy, filters,
              file_gamma = @getparam(writer."gamma"::Union{Float64, Nothing}))
    # TODO support `background`
    invokelatest(_write_png, dest, info; kwargs...)
end

createauto(::Type{DataLoader{:png}}, source::String) =
    !isnothing(match(r"\.png$"i, source))

createauto(::Type{DataWriter{:png}}, source::String) =
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
- `filters`: Either the number or string of: 0/"none", 1/"sub", 2/"up",
  3/"average", 4/"paeth" (default)

# Usage examples

```toml
[[someimage.loader]]
driver = "png"
```
"""
