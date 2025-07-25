# [Raw](@id storage-raw)

Access (read/write) values encoded in the data TOML file.

The `passthrough` loader is often useful when using this storage driver.

# Parameters

  * `value`: The value in question

# Usage examples

```toml
[[lifemeaning.storage]]
driver = "raw"
value = 42
```

```toml
[[parameters.storage]]
driver = "raw"
value = { a = 3, b = "*", c = false }
```


