module DataToolkitBase

using UUIDs, TOML, Dates

# For general usage
export loadcollection!, dataset

# For extension packages
export AbstractDataTransformer, DataStorage, DataLoader, DataWriter,
    DataSet, DataCollection, QualifiedType, Identifier
export load, storage, getstorage, putstorage, save, resolve
export STACK, DATA_CONFIG_RESERVED_ATTRIBUTES
export @use, @addpkg

# For plugin packages
export PLUGINS, Plugin, fromspec, tospec, DataAdvice, DataAdviceAmalgamation
export ReplCmd, REPL_CMDS, help, completions, allcompletions

include("model/types.jl")
include("model/globals.jl")

include("model/qualifiedtype.jl")
include("model/identification.jl")
include("model/advice.jl")
include("model/parameters.jl")
include("model/stack.jl")
include("model/parser.jl")
include("model/writer.jl")
include("model/usepkg.jl")
include("model/datatree.jl")

include("interaction/externals.jl")
include("interaction/display.jl")
include("interaction/repl.jl")

function __init__()
    isinteractive() && init_repl()
end

include("testing.jl")

end
