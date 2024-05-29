module ZipFileExt

using ZipFile
import DataToolkitCommon: _read_zip, FilePath

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
    if !isdir(dir) mkpath(dir) end
    zarchive = ZipFile.Reader(archive)
    if onlyfile isa String
        onlyfile = lstrip(onlyfile, '/')
    end
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

function _read_zip(from::IO, prefix::String, filename::Union{String, Nothing})
    if !isnothing(filename)
        zarchive = ZipFile.Reader(from)
        for file in zarchive.files
            if chopprefix(file.name, prefix) == filename
                return IOBuffer(read(file))
            end
        end
        error("File $prefix/$filename not found within zip.")
    else
        error("Cannot load entire zip to IO, must specify a particular file.")
    end
end

function _read_zip(from::IO, prefix::String)
    zarchive = ZipFile.Reader(from)
    Dict{FilePath, IO}(
        FilePath(chopprefix(file.name, prefix)) => IOBuffer(read(file))
        for file in zarchive.files
            if !endswith(file.name, "/") && !endswith(file.name, "\\"))
end

_write_zip(dest::IO, info::AbstractDict) =
    ZipFile.write(dest, info)

end
