# [Zip](@id saveload-zip)

Load the contents of zipped data

# Input/output

The `zip` driver expects data to be provided via `IO` or a `FilePath`.

It can load the contents to the following formats:

  * `Dict{FilePath, IO}`,
  * `Dict{String, IO}`,
  * `IO`,
  * an unzipped `FilePath`,
  * an unzipped `DirPath`.

# Required packages

  * `ZipFile`

# Parameters

  * `prefix`: a path prefix applied to `file`, and stripped from paths when reading to a `Dict`.
  * `file`: the file in the zip whose contents should be extracted, when producing `IO`.
  * `extract`: the path that the zip should be extracted to, when producing an unzipped `FilePath`.
  * `recursive`: when extracting to a `FilePath`, whether nested zips should be unzipped too.

# Usage examples

```toml
[[dictionary.loader]]
driver = "zip"
file = "dictionary.txt"
```


