# [XML](@id saveload-xml)

Load and write XML data.

# Input/output

The `xml` driver expects data to be provided via an `IO` stream.

This driver supports parsing to two data types:

  * `XML.LazyNode`
  * `XML.Node`

# Required packages

  * `XML`

# Usage examples

```toml
[[sample.loader]]
driver = "xml"
```


