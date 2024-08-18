module DataToolkitCore

using UUIDs, TOML, Dates

using PrecompileTools
using Preferences
using Base.Threads

# For general usage
export loadcollection!, dataset

# For extension packages
export AbstractDataTransformer, DataStorage, DataLoader, DataWriter,
    DataSet, DataCollection, QualifiedType, Identifier,
    SystemPath, FilePath, DirPath, LintItem, LintReport
export load, storage, getstorage, putstorage, save, getlayer, resolve, refine,
    parse_ident, supportedtypes, typeify, create, create!, createauto,
    createinteractive, createpriority, lint, invokepkglatest
export IdentifierException, UnresolveableIdentifier, AmbiguousIdentifier,
    PackageException, UnregisteredPackage, MissingPackage,
    DataOperationException, CollectionVersionMismatch, EmptyStackError,
    ReadonlyCollection, TransformerError, UnsatisfyableTransformer,
    OrphanDataSet, InvalidParameterType
export STACK, DATA_CONFIG_RESERVED_ATTRIBUTES
export @require, @addpkg, @dataplugin, @advise, @getparam, @log_do

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

include("interaction/logging.jl") # Need to be loaded early
include("interaction/typetransforms.jl")
include("interaction/externals.jl")
include("interaction/creation.jl")
include("interaction/manipulation.jl")
include("interaction/lint.jl")

include("precompile.jl")

function add_datasets! end # For `ext/AbstractTreesExt.jl`

end
