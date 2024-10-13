function _iotofilepath(loader::DataLoader)
    pathattr = @getparam loader."path"::Union{String, Nothing}
    path = if !isnothing(pathattr)
        expanduser(pathattr)
    else
        joinpath(tempdir(), string("julia_datatoolkit_iotofile_", loader.dataset.uuid))
    end
    abspath(dirof(loader.dataset.collection), path)
end

function load(loader::DataLoader{Symbol("io->file")}, from::FilePath, ::Type{FilePath})
    path = _iotofilepath(loader)
    # Remove non-symlinks, broken symlinks, and incorrect symlinks
    if isfile(path) && (!islink(path) || !isfile(realpath(path)) || realpath(path) != abspath(from.path))
        rm(path)
    end
    if !isfile(path)
        symlink(from.path, path)
    end
    FilePath(path)
end

function load(loader::DataLoader{Symbol("io->file")}, from::IO, ::Type{FilePath})
    path = _iotofilepath(loader)
    if !isfile(path) || @getparam loader."rewrite"::Bool false
        open(path, "w") do io
            write(io, from)
        end
    end
    FilePath(path)
end

const IOTOFILE_DOC = md"""
Obtain an IO as a FilePath

The `io->file` loader serves as a bridge between and backends that produce IO
but not a file path, and any subsequent transformers that require a file.

If a `FilePath` can be provided directly, `io->file` will be sneaky and just
create a symlink.

!!! warn
    If a file with the given path already exists, it is possible for the content
    to become out of date, set `rewrite` to write the file every access and so
    avoid this potential issue. This is not a risk in the symlink case.

# Input/output

The `io->file` driver accepts `IO` and produces a `FilePath`.

# Parameters

- `path`: A path to save the file to. If not set, a tempfile will be used.
- `rewrite`: Whether the any existing file should be overwritten afresh on each access.
"""
