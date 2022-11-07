"""
    unzip(archive::IO, dir::String=pwd();
        recursive::Bool=false, log::Bool=false)
Unzip an `archive` to `dir`.

If `recursive` is set, nested zip files will be recursively
unzipped too.

Set `log` to see unzipping progress.
"""
function unzip(archive::IO, dir::String=pwd();
               recursive::Bool=false, log::Bool=false)
    @use ZipFile
    if !isdir(dir) mkpath(dir) end
    zarchive = ZipFile.Reader(archive)
    for file in zarchive.files
        log && @info "(unzip) extracting $(file.name)"
        out_file = joinpath(dir, file.name)
        if endswith(file.name, "/") || endswith(file.name, "\\")
            mkdir(out_file)
        elseif endswith(file.name, ".zip")
            if recursive
                unzip(IOBuffer(read(file)),
                      joinpath(dir, first(splitext(file.name)));
                      recursive, log)
            else
                write(out_file, read(file))
            end
        else
            write(out_file, read(file))
        end
    end
    close(zarchive)
end

unzip(file::String, dir::String=dirname(file); recursive::Bool=false, log::Bool=false) =
    open(file) do io unzip(io, dir; recursive, log) end

function load(loader::DataLoader{:zip}, from::IO, ::Type{FilePath})
    @use ZipFile
    dir = if !isnothing(get(loader, "extract"))
        abspath(dirname(loader.dataset.collection.path),
                get(loader, "extract"))
    else
        joinpath(tempdir(), "jl_datatoolkit_zip_" * string(chash(loader), base=16))
    end
    if !isdir(dir)
        unzip(from, dir;
              recursive = get(loader, "recursive", false),
              log = should_log_event("unzip", loader))
    end
    FilePath(dir)
end

function load(loader::DataLoader{:zip}, from::IO, ::Type{IO})
    @use ZipFile
    filename = get(loader, "file")
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
    @use ZipFile
    zarchive = ZipFile.Reader(from)
    Dict{FilePath, IO}(FilePath(file.name) => IOBuffer(read(file))
                       for file in zarchive.files
                           if !endswith(file.name, "/") && !endswith(file.name, "\\"))
end

function load(loader::DataLoader{:zip}, from::IO, ::Type{Dict{String, IO}})
    Dict{String, IO}(string(fname) => io for (fname, io) in
                         load(loader, from, Dict{FilePath, IO}))
end

function load(loader::DataLoader{:zip}, from::FilePath,
              as::Type{<:Union{FilePath, IO, Dict{FilePath, IO}, Dict{String, IO}}})
    open(string(from)) do io load(loader, io, as) end
end
