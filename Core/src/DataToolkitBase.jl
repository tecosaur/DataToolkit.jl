module DataToolkitBase

using UUIDs, TOML, Dates

# For general usage
export loadcollection!, dataset

# For extension packages
export AbstractDataTransformer, DataStorage, DataLoader, DataWriter,
    DataSet, DataStore, DataCollection, QualifiedType, Identifier
export load, storage, getstorage, putstorage, writeinfo
export STACK, DATA_CONFIG_RESERVED_ATTRIBUTES

# For plugin packages
export PLUGINS, Plugin, fromspec, DataTransducer, DataTransducerAmalgamation
export ReplCmd, REPL_CMDS, help, completions, allcompletions

include("types.jl")
include("globals.jl")
include("constructors.jl")

include("display.jl")

include("internals.jl")
include("externals.jl")
include("writer.jl")

include("repl.jl")

function __init__()
    isinteractive() && init_repl()
end

include("testing.jl")

end
