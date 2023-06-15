function load(loader::DataLoader{:tar}, from::IO, ::Type{IO})
    @import Tar
    filepath = get(loader, "file")
    !isnothing(filepath) || error("Cannot load entire tarball to IO, must specify a particular file.")
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

function load(loader::DataLoader{:tar}, from::IO, ::Type{Vector{UInt8}})
    io = load(loader, from, IO)
    take!(io)
end

function load(loader::DataLoader{:tar}, from::IO, ::Type{String})
    io = load(loader, from, IO)
    String(take!(io))
end

function load(loader::DataLoader{:tar}, from::IO, ::Type{Dict{String, Vector{UInt8}}})
    @import Tar
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

function load(loader::DataLoader{:tar}, from::IO, ::Type{Dict{String, IO}})
    Dict{String, IO}(
        path => IOBuffer(bytes) for (path, bytes) in
            load(loader, from, Dict{String, Vector{UInt8}}))
end

function load(loader::DataLoader{:tar}, from::IO, ::Type{Dict{String, String}})
    Dict{String, String}(
        path => String(bytes) for (path, bytes) in
            load(loader, from, Dict{String, Vector{UInt8}}))
end

function load(loader::DataLoader{:tar}, from::IO, ::Type{Dict{FilePath, Vector{UInt8}}})
    Dict{String, Vector{UInt8}}(
        FilePath(path) => bytes for (path, bytes) in
            load(loader, from, Dict{String, Vector{UInt8}}))
end

function load(loader::DataLoader{:tar}, from::IO, ::Type{Dict{FilePath, IO}})
    Dict{FilePath, IO}(
        FilePath(path) => IOBuffer(bytes) for (path, bytes) in
            load(loader, from, Dict{String, Vector{UInt8}}))
end

function load(loader::DataLoader{:tar}, from::IO, ::Type{Dict{FilePath, String}})
    Dict{FilePath, String}(
        FilePath(path) => String(bytes) for (path, bytes) in
            load(loader, from, Dict{String, Vector{UInt8}}))
end

load(loader::DataLoader{:tar}, from::FilePath, as::Type) =
    open(io -> load(loader, io, as), string(from))

function supportedtypes(::Type{DataLoader{:tar}}, spec::SmallDict{String, Any})
    filetypes =
        [QualifiedType(:Core, :IO, ()),
         QualifiedType(:Core, :Array, (QualifiedType(:Core, :UInt8, ()), 1)),
         QualifiedType(:Core, :String, ())]
    dirtypes =
        [QualifiedType(:Base, :Dict, (QualifiedType(:DataToolkitBase, :FilePath, ()), QualifiedType(:Core, :IO, ()))),
         QualifiedType(:Base, :Dict, (QualifiedType(:DataToolkitBase, :FilePath, ()), QualifiedType(:Core, :Array, (QualifiedType(:Core, :UInt8, ()), 1)))),
         QualifiedType(:Base, :Dict, (QualifiedType(:DataToolkitBase, :FilePath, ()), QualifiedType(:Core, :String, ()))),
         QualifiedType(:Base, :Dict, (QualifiedType(:Core, :String, ()), QualifiedType(:Core, :IO, ()))),
         QualifiedType(:Base, :Dict, (QualifiedType(:Core, :String, ()), QualifiedType(:Core, :Array, (QualifiedType(:Core, :UInt8, ()), 1)))),
         QualifiedType(:Base, :Dict, (QualifiedType(:Core, :String, ()), QualifiedType(:Core, :String, ())))]
    if haskey(spec, "file")
        vcat(filetypes, dirtypes)
    else
        dirtypes
    end
end

createpriority(::Type{DataLoader{:tar}}) = 10

function create(::Type{DataLoader{:tar}}, source::String)
    if !isnothing(match(r"\.tar$"i, source)) ||
        !isnothing(match(r"^git://|^git(?:ea)?@|\w+@git\.|\.git$", source))
        ["file" => (; prompt="File: ", type=String, optional=true)]
    end
end

const TAR_DOC = md"""
Load the contents of a Tarball.

# Input/output

The `zip` driver expects data to be provided via `IO` or a `FilePath`.

It can load the contents to the following formats:
- `Dict{FilePath, IO}`
- `Dict{FilePath, Vector{UInt8}}`
- `Dict{FilePath, String}`
- `Dict{String, IO}`
- `Dict{String, Vector{UInt8}}`
- `Dict{String, String}`
- `IO` (single file)
- `Vector{UInt8}` (single file)
- `String` (single file)

# Required packages

- `Tar` (the stdlib)

# Parameters

- `file`: the file in the zip whose contents should be extracted, when producing `IO`.

# Usage examples

```toml
[[dictionary.loader]]
driver = "tar"
file = "dictionary.txt"
```
"""
