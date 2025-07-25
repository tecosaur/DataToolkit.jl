# [Filesystem](@id storage-filesystem)

Read and write access to local files

# Parameters

  * `path`: The path to the file in question, relative to the `Data.toml` if applicable, otherwise relative to the current working directory.

# Usage examples

```toml
[[iris.loader]]
driver = "filesystem"
path = "iris.csv"
```

```toml
[[iris.loader]]
driver = "filesystem"
path = "~/data/iris.csv"
```


