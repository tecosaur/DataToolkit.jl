module DataToolkitBase

using UUIDs, TOML, Dates

using PrecompileTools
using Compat

# For general usage
export loadcollection!, dataset

# For extension packages
export AbstractDataTransformer, DataStorage, DataLoader, DataWriter,
    DataSet, DataCollection, QualifiedType, Identifier, FilePath,
    LintItem, LintReport
export load, storage, getstorage, putstorage, save, getlayer, resolve, refine,
    parse_ident, supportedtypes, typeify, create, createpriority, lint
export IdentifierException, UnresolveableIdentifier, AmbiguousIdentifier,
    PackageException, UnregisteredPackage, MissingPackage,
    DataOperationException, CollectionVersionMismatch, EmptyStackError,
    ReadonlyCollection, TransformerError, UnsatisfyableTransformer,
    OrphanDataSet, InvalidParameterType
export STACK, DATA_CONFIG_RESERVED_ATTRIBUTES
export @require, @addpkg, @dataplugin, @advise, @getparam

# For plugin packages
export PLUGINS, PLUGINS_DOCUMENTATION, DEFAULT_PLUGINS, Plugin,
    fromspec, tospec, Advice, AdviceAmalgamation

include("model/types.jl")
include("model/globals.jl")
include("model/utils.jl")
include("model/advice.jl")
include("model/errors.jl")

include("model/qualifiedtype.jl")
include("model/identification.jl")
include("model/parameters.jl")
include("model/stack.jl")
include("model/parser.jl")
include("model/writer.jl")
include("model/usepkg.jl")
include("model/dataplugin.jl")

include("interaction/typetransforms.jl")
include("interaction/externals.jl")
include("interaction/display.jl")
include("interaction/manipulation.jl")
include("interaction/lint.jl")

include("precompile.jl")

function add_datasets! end # For `ext/AbstractTreesExt.jl`

end
