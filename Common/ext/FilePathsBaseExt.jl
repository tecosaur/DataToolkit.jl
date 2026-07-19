module FilePathsBaseExt

using FilePathsBase

using DataToolkitCore
import DataToolkitCore: load, save, getstorage, putstorage

# Storage/loaders provide the concrete `FilePath`/`DirPath`, not the abstract
# `SystemPath`, so both concrete forms are tried.
function getstorage(store::S, ::Type{AbstractPath}) where {S <: DataStorage}
    sp = @something(storage(store, FilePath, write=false),
                    storage(store, DirPath, write=false), Some(nothing))
    if !isnothing(sp) parse(AbstractPath, sp.path) end
end

function putstorage(store::S, path::AbstractPath) where {S <: DataStorage}
    P = if isdirpath(path) DirPath else FilePath end
    storage(store, P, write=true)
end

function load(loader::L, from::F, ::Type{AbstractPath}) where {L <: DataLoader, F}
    tryload(P) = if hasmethod(load, Tuple{L, F, Type{P}}) load(loader, from, P) end
    parse(AbstractPath, @something(tryload(FilePath), tryload(DirPath), return).path)
end

# Resolve ambiguity between the chain loader's load(::DataLoader{:chain}, ::Any, ::Type{T})
# and this extension's load(::DataLoader, ::Any, ::Type{AbstractPath}).
load(loader::DataLoader{:chain}, from, ::Type{AbstractPath}) =
    invoke(load, Tuple{DataLoader{:chain}, Any, Type{<:AbstractPath}}, loader, from, AbstractPath)

end
