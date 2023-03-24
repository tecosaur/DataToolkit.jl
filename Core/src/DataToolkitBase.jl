module DataToolkitBase

using UUIDs, TOML, Dates

using Compat

# For general usage
export loadcollection!, dataset

# For extension packages
export AbstractDataTransformer, DataStorage, DataLoader, DataWriter,
    DataSet, DataCollection, QualifiedType, Identifier, FilePath
export load, storage, getstorage, putstorage, save, resolve,
    supportedtypes, create, createpriority
export STACK, DATA_CONFIG_RESERVED_ATTRIBUTES
export @import, @addpkg, @dataplugin, @advise

# For plugin packages
export PLUGINS, PLUGINS_DOCUMENTATION, DEFAULT_PLUGINS, Plugin,
    fromspec, tospec, DataAdvice, DataAdviceAmalgamation
export ReplCmd, REPL_CMDS, help, completions, allcompletions,
    prompt, prompt_char, confirm_yn, peelword

include("model/types.jl")
include("model/globals.jl")

include("model/advice.jl")
include("model/qualifiedtype.jl")
include("model/identification.jl")
include("model/parameters.jl")
include("model/stack.jl")
include("model/parser.jl")
include("model/writer.jl")
include("model/usepkg.jl")
include("model/dataplugin.jl")
include("model/datatree.jl")

include("interaction/externals.jl")
include("interaction/display.jl")
include("interaction/manipulation.jl")
include("interaction/repl.jl")

function __init__()
    isinteractive() && init_repl()
end

end
