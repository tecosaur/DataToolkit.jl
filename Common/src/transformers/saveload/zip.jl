function unzip end # Implemented in `../../../ext/TOMLExt.jl`
function _read_zip end # Implemented in `../../../ext/TOMLExt.jl`

function load(loader::DataLoader{:zip}, from::IO, ::Type{FilePath})
    @require ZipFile
    extract = @getparam loader."extract"::Union{String, Nothing}
    path = if !isnothing(extract)
        abspath(dirof(loader.dataset.collection), extract)
    else
        joinpath(tempdir(), "jl_datatoolkit_zip_" * string(Store.rhash(loader), base=16))
    end
    prefix = rstrip(@getparam(loader."prefix"::String, ""), '/') * '/'
    file = @getparam loader."file"::Union{String, Nothing}
    filepath = if !isnothing(file) prefix * file end
    if !isdir(path) || (!isnothing(file) && !isfile(joinpath(path, file)))
        invokelatest(unzip,
                     from, path;
                     recursive = @getparam(loader."recursive"::Bool, false),
                     log = should_log_event("unzip", loader),
                     onlyfile = filepath)
    end
    if isnothing(file)
        FilePath(path)
    else
        FilePath(joinpath(path, file))
    end
end

function load(loader::DataLoader{:zip}, from::IO, ::Type{IO})
    @require ZipFile
    prefix = rstrip(@getparam(loader."prefix"::String, ""), '/') * '/'
    filename = @getparam loader."file"::Union{String, Nothing}
    invokelatest(_read_zip, from, prefix, filename)
end

function load(loader::DataLoader{:zip}, from::IO, ::Type{Dict{FilePath, IO}})
    @require ZipFile
    prefix = rstrip(@getparam(loader."prefix"::String, ""), '/') * '/'
    invokelatest(_read_zip, from, prefix)
end

function load(loader::DataLoader{:zip}, from::IO, ::Type{Dict{String, IO}})
    Dict{String, IO}(
        string(fname) => io for (fname, io) in
            DataToolkitBase.invokepkglatest(load, loader, from, Dict{FilePath, IO}))
end

function load(loader::DataLoader{:zip}, from::FilePath,
              as::Type{<:Union{FilePath, IO, Dict{FilePath, IO}, Dict{String, IO}}})
    open(string(from)) do io load(loader, io, as) end
end

createpriority(::Type{DataLoader{:zip}}) = 10

function create(::Type{DataLoader{:zip}}, source::String)
    if !isnothing(match(r"\.zip$"i, source))
        ["prefix" => (; prompt="Prefix: ", type=String, optional=true),
         "file" => (; prompt="File: ", type=String, optional=true),
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

- `prefix`: a path prefix applied to `file`, and stripped from paths when reading to a `Dict`.
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
