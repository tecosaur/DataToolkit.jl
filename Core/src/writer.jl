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
        dataset_parameters(adt.dataset, Val(:encode), adt.parameters))
end

function Base.convert(::Type{Dict}, ds::DataSet)
    merge(Dict("uuid" => string(ds.uuid),
               "store" => ds.store,
               "storage" => convert.(Dict, ds.storage),
               "loaders" => convert.(Dict, ds.loaders),
               "writers" => convert.(Dict, ds.writers)) |>
                   d -> filter(((k, v)::Pair) -> !isempty(v), d),
          dataset_parameters(ds, Val(:encode), ds.parameters))
end

function Base.convert(::Type{Dict}, s::DataStore)
    merge(Dict("name" => s.name),
          convert(Dict, s.storage))
end

function Base.convert(::Type{Dict}, dc::DataCollection)
    merge(Dict("data_config_version" => dc.version,
               "name" => dc.name,
               "uuid" => string(dc.uuid),
               "plugins" => dc.plugins,
               "data" => merge(
                   Dict("store" => convert.(Dict, dc.stores)),
                   dataset_parameters(dc, Val(:encode), dc.parameters))) |>
                       d -> filter((k, v)::Pair -> !isnothing(v), d),
          Dict(ds.name => convert(Dict, ds) for ds in dc.datasets))
end

Base.write(io::IO, dc::DataCollection) =
    TOML.print(io, convert(Dict, dc))

function Base.write(dc::DataCollection)
    if isnothing(dc.path)
        throw(ArgumentError("No collection writer is provided, so an IO argument must be given."))
    end
    write(dc, dc.path)
end

Base.write(ds::DataSet) = write(ds.collection)
Base.write(adt::AbstractDataTransformer) = write(adt.dataset)
