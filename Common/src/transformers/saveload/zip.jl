"""
    unzip(archive::IO, dir::String=pwd();
        recursive::Bool=false, log::Bool=false)
Unzip an `archive` to `dir`.

If `recursive` is set, nested zip files will be recursively
unzipped too.

Set `log` to see unzipping progress.
"""
function unzip(archive::IO, dir::String=pwd();
               recursive::Bool=false, log::Bool=false,
               onlyfile::Union{String, Nothing}=nothing)
    @import ZipFile
    if !isdir(dir) mkpath(dir) end
    zarchive = ZipFile.Reader(archive)
    for file in zarchive.files
        if isnothing(onlyfile) || file.name == onlyfile ||
            recursive && endswith(file.name, ".zip") && startswith(onlyfile, first(splitext(file.name)))
            log && @info "(unzip) extracting $(file.name)"
            out_file = joinpath(dir, file.name)
            isdir(dirname(out_file)) || mkpath(dirname(out_file))
            if endswith(file.name, "/") || endswith(file.name, "\\")
                mkdir(out_file)
            elseif endswith(file.name, ".zip")
                if recursive
                    unzip(IOBuffer(read(file)),
                          joinpath(dir, first(splitext(file.name)));
                          recursive, log, onlyfile = if !isnothing(onlyfile)
                              replace(onlyfile, file.name => "")
                          end)
                else
                    write(out_file, read(file))
                end
            else
                write(out_file, read(file))
            end
        end
    end
    close(zarchive)
end

unzip(file::String, dir::String=dirname(file); recursive::Bool=false, log::Bool=false) =
    open(file) do io unzip(io, dir; recursive, log) end

function load(loader::DataLoader{:zip}, from::IO, ::Type{FilePath})
    extract = @getparam loader."extract"::Union{String, Nothing}
    path = if !isnothing(extract)
        abspath(dirof(loader.dataset.collection), extract)
    else
        joinpath(tempdir(), "jl_datatoolkit_zip_" * string(Store.rhash(loader), base=16))
    end
    file = @getparam loader."file"::Union{String, Nothing}
    if !isdir(path) || !isnothing(file) && !isfile(joinpath(path, file))
        unzip(from, path;
              recursive = @getparam(loader."recursive"::Bool, false),
              log = should_log_event("unzip", loader),
              onlyfile = file)
    end
    if isnothing(file)
        FilePath(path)
    else
        FilePath(joinpath(path, file))
    end
end

function load(loader::DataLoader{:zip}, from::IO, ::Type{IO})
    @import ZipFile
    filename = @getparam loader."file"::Union{String, Nothing}
    if !isnothing(filename)
        zarchive = ZipFile.Reader(from)
        for file in zarchive.files
            if file.name == filename
                return IOBuffer(read(file))
            end
        end
        error("File $filename not found within zip.")
    else
        error("Cannot load entire zip to IO, must specify a particular file.")
    end
end

function load(::DataLoader{:zip}, from::IO, ::Type{Dict{FilePath, IO}})
    @import ZipFile
    zarchive = ZipFile.Reader(from)
    Dict{FilePath, IO}(FilePath(file.name) => IOBuffer(read(file))
                       for file in zarchive.files
                           if !endswith(file.name, "/") && !endswith(file.name, "\\"))
end

function load(loader::DataLoader{:zip}, from::IO, ::Type{Dict{String, IO}})
    Dict{String, IO}(string(fname) => io for (fname, io) in
                         DataToolkitBase.invokepkglatest(load, loader, from, Dict{FilePath, IO}))
end

function load(loader::DataLoader{:zip}, from::FilePath,
              as::Type{<:Union{FilePath, IO, Dict{FilePath, IO}, Dict{String, IO}}})
    open(string(from)) do io load(loader, io, as) end
end

createpriority(::Type{DataLoader{:zip}}) = 10

function create(::Type{DataLoader{:zip}}, source::String)
    if !isnothing(match(r"\.zip$"i, source))
        ["file" => (; prompt="File: ", type=String, optional=true),
         "extract" => function (spec)
             if !haskey(spec, "file")
                 (; prompt="Extract: ", type=String, optional=true)
             end
         end]
    end
end

const ZIP_DOC = md"""
Load the contents of zipped data

# Input/output

The `zip` driver expects data to be provided via `IO` or a `FilePath`.

It can load the contents to the following formats:
- `Dict{FilePath, IO}`,
- `Dict{String, IO}`,
- `IO`, and
- an unzipped `FilePath`.

# Required packages

- `ZipFile`

# Parameters

- `file`: the file in the zip whose contents should be extracted, when producing `IO`.
- `extract`: the path that the zip should be extracted to, when producing an
  unzipped `FilePath`.
- `recursive`: when extracting to a `FilePath`, whether nested zips should be
  unzipped too.

# Usage examples

```toml
[[dictionary.loader]]
driver = "zip"
file = "dictionary.txt"
```
"""
