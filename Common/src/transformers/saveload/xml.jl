function _read_xml end # Implemented in `../../../ext/XMLExt.jl`
function _write_xml end # Implemented in `../../../ext/XMLExt.jl`

function load(loader::DataLoader{:xml}, from::IO, as::Type)
    @require XML
    QualifiedType(as) ∈ (QualifiedType(:XML, :Node), QualifiedType(:XML, :LazyNode)) || return
    invokelatest(_read_xml, from, as)
end

supportedtypes(::Type{DataLoader{:xml}}) =
    [QualifiedType(:XML, :LazyNode), QualifiedType(:XML, :Node)]

function save(writer::DataWriter{:xml}, dest::IO, data)
    @require XML
    QualifiedType(typeof(data)) == QualifiedType(:XML, :Node) || return
    invokelatest(_write_xml, dest, data)
end

function createauto(::Type{DataLoader{:xml}}, source::String)
    !isnothing(match(r"\.xml$"i, source))
end

const XML_DOC = md"""
Load and write XML data.

# Input/output

The `xml` driver expects data to be provided via an `IO` stream.

This driver supports parsing to two data types:
- `XML.LazyNode`
- `XML.Node`

# Required packages

- `XML`

# Usage examples

```toml
[[sample.loader]]
driver = "xml"
```
"""
