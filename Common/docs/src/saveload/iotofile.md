# [IO to File](@id saveload-io to file)

Obtain an IO as a FilePath

The `io->file` loader serves as a bridge between and backends that produce IO but not a file path, and any subsequent transformers that require a file.

If a `FilePath` can be provided directly, `io->file` will be sneaky and just create a symlink.

!!! warn
    If a file with the given path already exists, it is possible for the content to become out of date, set `rewrite` to write the file every access and so avoid this potential issue. This is not a risk in the symlink case.


# Input/output

The `io->file` driver accepts `IO` and produces a `FilePath`.

# Parameters

  * `path`: A path to save the file to. If not set, a tempfile will be used.
  * `rewrite`: Whether the any existing file should be overwritten afresh on each access.


