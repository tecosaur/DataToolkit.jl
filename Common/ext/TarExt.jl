module TarExt

using Tar
import DataToolkitCommon: _read_tar

function _read_tar(from::IO, filepath::Union{String, Nothing})
    buf = Vector{UInt8}(undef, Tar.DEFAULT_BUFFER_SIZE)
    io = IOBuffer()
    Tar.read_tarball(_ -> true, from; buf) do header, _
        if header.path == filepath
            if header.type === :file
                Tar.read_data(from, io; size=header.size, buf)
            else
                @warn "Found $(sprint(show, filepath)), but it is a $(header.type) not a normal file."
            end
        end
    end
    io.size > 0 || error("Could not find the file $(sprint(show, filepath)) in the tarball")
    io
end

function _read_tar(from::IO, ::Type{Dict{String, Vector{UInt8}}})
    data = Dict{String, Vector{UInt8}}()
    buf = Vector{UInt8}(undef, Tar.DEFAULT_BUFFER_SIZE)
    io = IOBuffer()
    Tar.read_tarball(_ -> true, from; buf=buf) do header, _
        if header.type == :file
            take!(io) # In case there are multiple entries for the file
            Tar.read_data(from, io; size=header.size, buf)
            data[header.path] = take!(io)
        end
    end
    data
end

end
