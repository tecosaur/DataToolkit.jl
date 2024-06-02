module FilePathsBaseExt

using FilePathsBase

using DataToolkitCore
import DataToolkitCore: load, save, getstorage, putstorage

function getstorage(store::S, ::Type{AbstractPath}) where {S <: DataStorage}
    if hasmethod(getstorage, Tuple{S, FilePath})
        fp = @advise storage(store, FilePath, write=false)
        isnothing(fp) && return
        parse(AbstractPath, fp.path)
    end
end

function putstorage(store::S, path::AbstractPath) where {S <: DataStorage}
    if hasmethod(putstorage, Tuple{S, FilePath})
        @advise storage(store, FilePath(string(path)), write=true)
    end
end

function load(loader::L, from::F, ::Type{AbstractPath}) where {L <: DataLoader, F}
    if hasmethod(load, Tuple{L, F, FilePath})
        fp = @advise load(loader, from, FilePath)
        isnothing(fp) && return
        parse(AbstractPath, fp.path)
    end
end

end
