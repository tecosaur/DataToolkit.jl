module ZipArchivesExt

using ZipArchives
using DataToolkitCore: FilePath
import DataToolkitCommon: unzip, _read_zip, _write_zip

"""
    unzip(archive::Vector{UInt8}, dir::String=pwd();
        recursive::Bool=false)

Unzip an `archive` to `dir`.

If `recursive` is set, nested zip files will be recursively
unzipped too.
"""
function unzip(archive::Vector{UInt8}, dir::String=pwd();
               recursive::Bool=false, onlyfile::Union{String, Nothing}=nothing)
    if !isdir(dir) mkpath(dir) end
    zarchive = ZipReader(archive)
    if onlyfile isa String
        onlyfile = lstrip(onlyfile, '/')
    end
    for filename in zip_names(zarchive)
        if filename == ".." || startswith(filename, "../") ||
            endswith(filename, "/..") || occursin("/../", filename) ||
            isabspath(filename) || occursin(r"^[A-Za-z]:", filename)
            @warn "Skipping potentially unsafe path: $filename"
            continue
        end
        if !isnothing(onlyfile) && filename != onlyfile &&
            !(recursive && endswith(filename, ".zip") && startswith(onlyfile, first(splitext(filename))))
            continue
        end
        out_file = joinpath(dir, filename)
        isdir(dirname(out_file)) || mkpath(dirname(out_file))
        if endswith(filename, "/") || endswith(filename, "\\")
            mkdir(out_file)
        elseif endswith(filename, ".zip")
            if recursive
                unzip(zip_readentry(zarchive, filename),
                      joinpath(dir, first(splitext(filename)));
                      recursive, onlyfile = if !isnothing(onlyfile)
                          chopprefix(onlyfile, first(splitext(filename)) * "/")
                      end)
            else
                zip_openentry(io -> write(out_file, io), zarchive, filename)
            end
        else
            zip_openentry(io -> write(out_file, io), zarchive, filename)
        end
    end
end

unzip(file::String, dir::String=dirname(file); recursive::Bool=false) =
    unzip(read(file), dir; recursive)

function _read_zip(from::Vector{UInt8}, prefix::String, filename::Union{String, Nothing})
    if !isnothing(filename)
        zarchive = ZipReader(from)
        for file in zip_names(zarchive)
            chopprefix(file, prefix) == filename &&
                return zip_readentry(zarchive, file)
        end
        error("File $prefix/$filename not found within zip.")
    else
        error("Cannot load entire zip to IO, must specify a particular file.")
    end
end

function _read_zip(from::Vector{UInt8}, prefix::String)
    zarchive = ZipReader(from)
    Dict{FilePath, Vector{UInt8}}(
        FilePath(chopprefix(filename, prefix)) => zip_readentry(zarchive, filename)
        for filename in zip_names(zarchive)
            if !endswith(filename, "/") && !endswith(filename, "\\"))
end

function _write_zip(dest::IO, info::AbstractDict)
    zio = ZipWriter(dest)
    for (key, val) in info
        zip_newfile(zio, string(key))
        write(zio, val)
    end
    close(zio)
end

end
