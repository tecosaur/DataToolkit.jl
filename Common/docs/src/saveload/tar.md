# [Tar](@id saveload-tar)

Load the contents of a Tarball.

# Input/output

The `zip` driver expects data to be provided via `IO` or a `FilePath`.

It can load the contents to the following formats:

  * `Dict{FilePath, IO}`
  * `Dict{FilePath, Vector{UInt8}}`
  * `Dict{FilePath, String}`
  * `Dict{String, IO}`
  * `Dict{String, Vector{UInt8}}`
  * `Dict{String, String}`
  * `IO` (single file)
  * `Vector{UInt8}` (single file)
  * `String` (single file)

# Required packages

  * `Tar` (the stdlib)

# Parameters

  * `file`: the file in the zip whose contents should be extracted, when producing `IO`.

# Usage examples

```toml
[[dictionary.loader]]
driver = "tar"
file = "dictionary.txt"
```


