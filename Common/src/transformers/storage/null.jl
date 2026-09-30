storage(::DataStorage{:null}, ::Type{Nothing}; write::Bool) = Some(nothing)

const NULL_S_DOC = md"""
Provide no data, for loaders that need no input

Some loaders construct their information without reading anything, such as a
`julia` loader without an `input`. The `null` driver says so explicitly: it
provides `nothing`, so only a loader that accepts no input can use it.

# Usage examples

```toml
[[answer.storage]]
driver = "null"

[[answer.loader]]
driver = "julia"
function = "() -> 42"
type = "Int"
```
"""
