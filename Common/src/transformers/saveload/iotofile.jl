function load(loader::DataLoader{Symbol("io->file")}, from::IO, ::Type{FilePath})
    path = abspath(dirof(loader.dataset.collection),
                   @something(expanduser(get(loader, "path")),
                              joinpath(tempdir(),
                                       string("julia_datatoolkit_iotofile_",
                                              loader.dataset.uuid))))
    if !isfile(path)
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

# Input/output

The `io->file` driver accepts `IO` and produces a `FilePath`.

# Parameters

- `path`: A path to save the file to. If not set, a tempfile will be used.
"""
