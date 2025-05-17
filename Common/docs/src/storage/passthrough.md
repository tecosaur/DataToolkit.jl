# [Passthrough](@id storage-passthrough)

Use a data set as a storage source

The `passthrough` storage driver enables dataset redirection by offering the loaded result of another data set as a *read-only* storage transformer.

Write capability may be added in future.

# Parameters

  * `source`: The identifier of the source dataset to be loaded.

# Usage examples

```toml
[[iris2.storage]]
driver = "passthrough"
source = "iris1"
```


