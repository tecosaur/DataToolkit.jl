module DataToolkitCore

using UUIDs, TOML, Dates

using PrecompileTools
using Preferences
using Base.Threads

# NOTE: We export so many symbols because this package is
# specifically intended as a dependency for other packages
# that are building a more general-purpose DataToolkit package.
# This means we want to prioritise convenience over avoiding
# concerns about namespace pollution, since this huge list of
# exports will not be visible to indirect users of this package.

# Useful types
export DataCollection, DataSet, Identifier, QualifiedType,
    DataTransformer, DataStorage, DataLoader, DataWriter
# Overload targets
export load, save, storage, getstorage, putstorage, supportedtypes,
    createinteractive, createauto, createpriority
# Implementing a transformer/plugin
export @advise, @getparam
# Retrieval functions
export loadcollection!, getlayer, dataset, resolve, refine, parse_ident, typeify
# Creation functions
export create, create!, dataset!, storage!, loader!, writer!
# Manipulation functions
export stack_index, stack_move, stack_remove!,
    plugin_add, plugin_remove, plugin_info, plugin_list,
    config_get, config_set, config_unset
# Package loading
export @require, @addpkg, addpkg, invokepkglatest
# Linting
export LintReport, LintItem, lint, lintfix
# Useful utils
export SystemPath, FilePath, DirPath, @log_do, @getparam, atomic_write
# Custom exceptions
export IdentifierException, UnresolveableIdentifier, AmbiguousIdentifier,
    PackageException, UnregisteredPackage, MissingPackage,
    DataOperationException, CollectionVersionMismatch, EmptyStackError,
    ReadonlyCollection, TransformerError, UnsatisfyableTransformer,
    OrphanDataSet, InvalidParameterType, ImpossibleTypeException
# Key variables
export STACK, DATA_CONFIG_RESERVED_ATTRIBUTES
# Plugin system components
export PLUGINS, PLUGINS_DOCUMENTATION, DEFAULT_PLUGINS, Plugin,
    @dataplugin, fromspec, tospec, Advice, AdviceAmalgamation

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
include("interaction/display.jl")
include("interaction/lint.jl")

include("precompile.jl")

function add_datasets! end # For `ext/AbstractTreesExt.jl`

end
