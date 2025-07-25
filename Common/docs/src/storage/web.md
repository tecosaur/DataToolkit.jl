# [Web](@id storage-web)

Fetch data from the internet

This pairs well with the `store` plugin.

# Required packages

  * `Downloads` (part of Julia's stdlib)

# Parameters

  * `url` :: Path to the online data.
  * `headers` :: HTTP headers that should be set.
  * `timeout` :: Maximum number of seconds to try to download for before abandoning.

# Usage examples

Downloading the data on-demand each time it is accessed.

```toml
[[iris.storage]]
driver = "web"
url = "https://raw.githubusercontent.com/mwaskom/seaborn-data/master/iris.csv"
```


