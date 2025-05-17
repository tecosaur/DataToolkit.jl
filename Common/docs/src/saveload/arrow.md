# [Arrow](@id saveload-arrow)

Parse and serialize arrow files

# Input/output

The `arrow` driver expects data to be provided via `IO`.

By default this driver supports parsing to two data types:

  * `DataFrame`
  * `Arrow.Table`

# Required packages

  * `Arrow`

# Parameters

  * `convert`: controls whether certain arrow primitive types will be converted to more friendly Julia defaults
  * The writer mirrors the arguments available in `Arrow.write`.

# Usage examples

```toml
[[iris.loader]]
driver = "arrow"
```


