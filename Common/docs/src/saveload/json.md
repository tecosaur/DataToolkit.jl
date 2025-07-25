# [Json](@id saveload-json)

Parse and serialize JSON data

# Input/output

The `json` driver expects data to be provided via `IO`.

It will parse to a number of types depending on the input:

  * `JSON3.Object`
  * `JSON3.Array`
  * `String`
  * `Number`
  * `Boolean`
  * `Nothing`

If you do not wish to impose any expectations on the parsed type, you can ask for the data of type `Any`.

When writing, any type compatible with `JSON3.write` can be used directly, with any storage backend supporting `IO`.

# Required packages

  * `JSON3`

# Parameters

  * `pretty`: Whether to use `JSON3.pretty` when writing

# Usage examples

```toml
[[sample.loader]]
driver = "json"
```


