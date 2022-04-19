# Data Transduction

## Transduction

```@docs
DataTransducer
```

## Transduction points

### Construction of data sets and collections

`DataCollection`s, `DataStore`s, and `AbstractDataTransformer`s are transduced
at two stages during construction:
1. When calling `fromspec` on the `Dict` representation, at the start of construction
2. At the end of construction, calling `identity` on the object

The signatures of the transduced function calls are as follows:
```julia
fromspec(DataCollection, spec::Dict{String, Any}; path::Union{String, Nothing})
identity(DataCollection)
```

```julia
fromspec(DataSet, collection::DataCollection, name::String, spec::Dict{String, Any})
identity(DataSet)
```

```julia
fromspec(ADT::Type{<:AbstractDataTransformer}, dataset::DataSet, spec::Dict{String, Any})
identity(ADT::AbstractDataTransformer)
```

### Processing identifiers

Both the parsing of an `Identifier` from a string, and the serialisation of an `Identifier` to a string are transduced. Specifically, the following function calls:
```julia
parse(Identifier, spec::AbstractString, transduced=true)
string(ident::Identifier)
```

### The data flow arrows

The reading, writing, and storage of data may all be transduced. Specifically,
the following function calls:
```julia
load(loader::DataLoader, datahandle, as::Type)
storage(provider::DataStorage, as::Type; write::Bool)
writeinfo(writer::DataWriter, datahandle, info)
```
