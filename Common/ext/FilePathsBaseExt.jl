module FilePathsBaseExt

using FilePathsBase

using DataToolkitCore
import DataToolkitCore: load, save, getstorage, putstorage

function getstorage(store::S, ::Type{AbstractPath}) where {S <: DataStorage}
    if hasmethod(getstorage, Tuple{S, DataToolkitCore.SystemPath})
        fp = @advise storage(store, DataToolkitCore.SystemPath, write=false)
        isnothing(fp) && return
        parse(AbstractPath, fp.path)
    end
end

function putstorage(store::S, path::AbstractPath) where {S <: DataStorage}
    if hasmethod(putstorage, Tuple{S, DataToolkitCore.SystemPath})
        @advise storage(store, DataToolkitCore.SystemPath(string(path)), write=true)
    end
end

function load(loader::L, from::F, ::Type{AbstractPath}) where {L <: DataLoader, F}
    if hasmethod(load, Tuple{L, F, DataToolkitCore.SystemPath})
        fp = @advise load(loader, from, DataToolkitCore.SystemPath)
        isnothing(fp) && return
        parse(AbstractPath, fp.path)
    end
end

end
