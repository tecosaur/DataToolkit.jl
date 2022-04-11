struct DriverUnimplementedException <: Exception
    transform::AbstractDataTransformer
    driver::Symbol
    method::Symbol
end

function Base.convert(::Type{Type}, qt::QualifiedType)
    getfield(getfield(Main, qt.parentmodule), qt.name)
end

Base.methods(dt::DataTransducer) = methods(dt.f)
function (dt::DataTransducer)(context, transformfn::Function, args::Tuple, kargs::NamedTuple)
    if applicable(dt.f, context, transformfn, args, kargs)
        dt.f(context, transformfn, args, kargs)
    else
        (context, transformfn, args, kargs) # act as identiy fuction
    end
end

function Base.read(dataset::DataSet, as::Type)
    loaderfuncsall = filter(l -> length(l.sig.types) == 4, methods(load).ms)
    qtype = QualifiedType(as)
    # Surely there's a better way?
    for loader in dataset.loaders
        if qtype in loader.supports
            loaderfuncs = filter(l -> loader <: l.sig.types[2], loaderfuncsall)
            for storage in dataset.storage
                for lfunc in loaderfuncs
                    for stype in convert.(Type, storage.supports)
                        if stype isa lfunc.sig.types[3] || stype <: lfunc.sig.types[3]
                            load(loader, open(stype, dataset), as)
                        end
                    end
                end
            end
        end
    end
end

function Base.open(as::Type, data::DataSet)
    qtype = QualifiedType(as)
    for storage in data.storage
        if qtype in storage.supports
            return Base.open(storage, as) # TODO module support
        end
    end
    # throw unimplemented error?
end
Base.open(qas::QualifiedType, data::DataSet) =
    Base.open(convert(Type, qas), data)



function load(loader::DataLoader{driver}, source, as) where {driver}

end

function getloaders(loader::DataLoader, )

end

function getstorage()

end
