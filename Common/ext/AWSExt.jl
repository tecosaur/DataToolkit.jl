module AWSExt

using AWS
@service S3

import DataToolkitCommon: _read_s3

const AWS_MAX_ATTEMPTS = 3

function aws_config(region::Union{String, Nothing})
    gconf = global_aws_config(creds=nothing)
    AWSConfig(creds = gconf.credentials,
              region = something(region, gconf.region),
              output = gconf.output,
              max_attempts = AWS_MAX_ATTEMPTS)
end

function _read_s3(bucket::String, object::String, ::Type{IO};
                  region::Union{String, Nothing}, params::Dict{String,Any})
    conf = aws_config(region)
    sparams = merge(params, Dict{String,Any}(
        "response_stream" => Base.BufferStream(),
        "return_stream" => true))
    stream = S3.get_object(bucket, object, sparams; aws_config=conf)
    stream
end

function _read_s3(bucket::String, object::String, dest::IO; kwargs...)
    stream = _read_s3(bucket, object, IO; kwargs...)
    while !eof(stream)
        write(dest, readavailable(stream))
    end
    dest
end

end
