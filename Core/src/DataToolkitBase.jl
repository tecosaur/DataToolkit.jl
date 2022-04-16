module DataToolkitBase

using UUIDs, TOML, Dates

export AbstractDataTransformer, DataStorage, DataLoader, DataWriter,
    DataSet, DataStore, DataCollection, QualifiedType, Identifier,
    DataTransducer, DataTransducerAmalgamation

export PLUGINS, Plugin, fromtoml, load, storage

include("types.jl")
include("globals.jl")
include("constructors.jl")

include("display.jl")

include("internals.jl")
include("externals.jl")
include("writer.jl")

include("testing.jl")

end
