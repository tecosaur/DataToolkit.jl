# [Chain](@id saveload-chain)

Chain multiple transformers together

# Input/Output

The `chain` loader can accept any form of input, and produce any form of output.

In passes the initial input through a *chain* of other loaders, via the `loader` property. A list of loader driver names can be given to chain together those loaders with no properties. To provide properties, use a TOML array of tables and specify the full (`driver = "name", ...`) form.

Writing is not currently supported.

# Usage examples

```toml
[[iris.loader]]
driver = "chain"
loaders = ["gzip", "csv"]
```

```toml
[[iris.loader]]
driver = "chain"
loaders = ["gzip", { driver = "tar", file = "iris.csv" }, "csv"]
```

```toml
[[chained.loader]]
driver = "chain"

    [[chained.loader.loaders]]
    driver = "gzip"

    [[chained.loader.loaders]]
    driver = "csv"

    [[chained.loader.loaders]]
    driver = "julia"
    input = "DataFrame"
    path = "scripts/custom_postprocessing.jl"
    type = "DataFrame"
```


