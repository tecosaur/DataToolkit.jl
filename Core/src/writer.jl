function Base.string(q::QualifiedType)
    if q.parentmodule in (:Base, :Core)
        string(q.name)
    else
        string(q.parentmodule, '.', q.name)
    end
end

function Base.convert(::Type{Dict}, adt::AbstractDataTransformer)
    merge(Dict("supports" => string.(adt.supports),
               "priority" => adt.priority),
        adt.arguments)
end

function Base.convert(::Type{Dict}, ds::DataSet)
    merge(Dict("uuid" => string(ds.uuid),
               "store" => ds.store,
               "storage" => convert.(Dict, ds.storage),
               "loaders" => convert.(Dict, ds.loaders),
               "writers" => convert.(Dict, ds.writers)) |>
                   d -> filter(((k, v)::Pair) -> !isempty(v), d),
          ds.parameters)
end

function Base.convert(::Type{Dict}, s::DataStore)
    merge(Dict("name" => s.name),
          convert(Dict, s.storage))
end

function Base.convert(::Type{Dict}, dc::DataCollection)
    merge(Dict("data_config_version" => dc.version,
               "name" => dc.name,
               "uuid" => string(dc.uuid),
               "data" => Dict{String,Any}(
                   "defaults" => dc.defaults,
                   "plugins" => dc.plugins,
                   "store" => convert.(Dict, dc.stores))),
          Dict(ds.name => convert(Dict, ds) for ds in dc.datasets))
end

Base.write(io::IO, dc::DataCollection) =
    TOML.print(io, convert(Dict, dc))

function Base.write(dc::DataCollection)
    if isnothing(dc.writer)
        throw(ArgumentError("No collection writer is provided, so an IO argument must be given."))
    end
    dc.writer(dc)
end

Base.write(ds::DataSet) = write(ds.collection)
Base.write(adt::AbstractDataTransformer) = write(adt.dataset)
