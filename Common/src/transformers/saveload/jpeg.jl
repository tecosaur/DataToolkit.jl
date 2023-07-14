function load(loader::DataLoader{:jpeg}, from::IO, ::Type{Matrix})
    @import JpegTurbo.jpeg_decode
    @import ColorTypes: Gray
    kwargs = (transpose = @getparam(loader."transpose"::Bool, false),
              scale_ratio = @getparam(loader."scale_ratio"::Real, 1))
    # TODO support `preferred_size`
    if @getparam loader."grayscale"::Bool false
        jpeg_decode(Gray, from; kwargs...)
    else
        jpeg_decode(from; kwargs...)
    end
end

function save(writer::DataWriter{:jpeg}, dest::IO, info::Matrix)
    @import JpegTurbo.jpeg_encode
    kwargs = (transpose = @getparam(loader."transpose"::Bool, false),
              quality = @getparam(loader."quality"::Int, 92))
    jpeg_encode(dest, info; kwargs...)
end

create(::Type{DataLoader{:jpeg}}, source::String) =
    !isnothing(match(r"\.jpe?g$"i, source))

create(::Type{DataWriter{:jpeg}}, source::String) =
    !isnothing(match(r"\.jpe?g$"i, source))

const JPEG_DOC = md"""
Encode and decode JPEG images

# Input/output

The `jpeg` driver expects data to be provided via `IO`.

It will parse to a `Matrix{<:Colorant}`.

# Required packages

- `JpegTurbo`

# Parameters

## Reader

- `transpose`: Whether to permute the image's width and height dimension
- `scale_ratio`: scale the image this ratio in `M/8` with `M ∈ 1:16` (values
  will be mapped to the closest value)
- `grayscale`: Whether to process the image in grayscale

## Writer

- `transpose`: Whether to permute the image's width and height dimension
- `quality`: The IJG-scale JPEG quality value, between 0 and 100.

# Usage examples

```toml
[[someimage.loader]]
driver = "jpeg"
```
"""
