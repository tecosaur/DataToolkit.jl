# [Serialization](@id saveload-serialization)

Load and write arbitrary Julia objects.

The `serialization` driver uses Julia's built-in `Serialization` library to *serialize* and *deserialize* Julia objects. This should be used with caution, as it can be a security risk if the serialized data is from an untrusted source.

Also note that that successful deserialization often requires the same or newer version of Julia and the same package versions that were used to serialize the data.

# Input/output

The `serialization` driver reads and writes to IO and files.

# Usage examples

```toml
[[iris.loader]]
driver = "serialization"
```


