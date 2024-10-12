function _read_s3 end # Implemented in `../../../ext/AWSExt.jl`

function aws_params(storage::DataStorage{:s3})
    params = Dict{String, Any}()
    let version = @getparam storage."version"::Union{String, Nothing} nothing
        if !isnothing(version)
            params["versionId"] = version
        end
    end
    headers = convert(Dict, @getparam storage."headers"::Dict{String, Any})
    let byte_range = @getparam storage."byte_range"::Union{Vector, Nothing} nothing
        if isnothing(byte_range)
        elseif length(byte_range) == 2
            start, stop = byte_range .- 1
            headers["Range"] = "bytes=$start-$stop"
        elseif all(typeof.(byte_range) .== Int)
            @warn "S3 byte range should be of the form [Int, Int], not [$(join(typeof.(byte_range), ", "))], ignoring."
        else
            @warn "S3 byte range should be of length 2, not $(length(byte_range)), ignoring."
        end
    end
    if !isempty(headers)
        params["headers"] = headers
    end
    params
end

function getstorage(storage::DataStorage{:s3}, ::Type{FilePath})
    @require AWS
    bucket = @getparam storage."bucket"::String
    object = @getparam storage."object"::String
    region = @getparam storage."region"::Union{String, Nothing} nothing
    params = aws_params(storage)
    savetofile(storage) do io
        @log_do("load:s3",
                "Downloading s3://$(bucket)/$(object)...",
                invokelatest(_read_s3, bucket, object, io; region, params))
    end
end

function createauto(::Type{DataStorage{:s3}}, source::String)
    if startswith(source, "s3://")
        bucket, object = split(chopprefix(source, "s3://"), '/', limit=2)
        Dict("bucket" => bucket, "object" => object)
    end
end

const S3_DOC = md"""
Fetch data from an S3 bucket.

# Required packages

- `AWS`

# Parameters

- `bucket`: The name of the S3 bucket.
- `object`: The name of the object within the bucket.
- `region`: The AWS region in which the bucket is located.
- `version`: The version of the object to fetch.
- `headers`: A dictionary of headers to pass to the request.
- `byte_range`: A two-element vector of integers specifying the byte range to fetch.

# Usage examples

```toml
[[iris.loader]]
driver = "s3"
bucket = "mybucket"
object = "path/to/iris.csv"
```
"""
