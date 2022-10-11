function Base.string(q::QualifiedType)
    if haskey(QUALIFIED_TYPE_SHORTHANDS.reverse, q)
        return QUALIFIED_TYPE_SHORTHANDS.reverse[q]
    end
    qname = if q.parentmodule in (:Base, :Core)
        string(q.name)
    else
        string(q.parentmodule, '.', q.name)
    end
    if isempty(q.parameters)
        qname
    else
        parstr = map(q.parameters) do p
            if p isa Symbol
                string(':', p)
            else string(p) end
        end
        string(qname, '{', join(parstr, ','), '}')
    end
end

function Base.convert(::Type{Dict}, adt::AbstractDataTransformer)
    adt.dataset.collection.advise(tospec, adt)
end

function tospec(adt::AbstractDataTransformer)
    merge(Dict("driver" => string(first(typeof(adt).parameters)),
               "support" => string.(adt.support),
               "priority" => adt.priority),
        dataset_parameters(adt.dataset, Val(:encode), adt.parameters))
end

function Base.convert(::Type{Dict}, ds::DataSet)
    ds.collection.advise(tospec, ds)
end

function tospec(ds::DataSet)
    merge(Dict("uuid" => string(ds.uuid),
               "storage" => convert.(Dict, ds.storage),
               "loader" => convert.(Dict, ds.loaders),
               "writer" => convert.(Dict, ds.writers)) |>
                   d -> filter(((k, v)::Pair) -> !isempty(v), d),
          dataset_parameters(ds, Val(:encode), ds.parameters))
end

function Base.convert(::Type{Dict}, dc::DataCollection)
    dc.advise(tospec, dc)
end

function tospec(dc::DataCollection)
    merge(Dict("data_config_version" => dc.version,
               "name" => dc.name,
               "uuid" => string(dc.uuid),
               "plugins" => dc.plugins,
               "config" => dataset_parameters(dc, Val(:encode), dc.parameters)),
          let datasets = Dict{String, Any}()
              for ds in dc.datasets
                  if haskey(datasets, ds.name)
                      push!(datasets[ds.name], convert(Dict, ds))
                  else
                      datasets[ds.name] = [convert(Dict, ds)]
                  end
              end
              datasets
          end)
end

Base.write(io::IO, dc::DataCollection) =
    TOML.print(io, filter(((_, value),) -> !isnothing(value) && !isempty(value),
                          convert(Dict, dc));
               sorted = true, by = k -> get(DATA_CONFIG_KEY_SORT_MAPPING, k, lowercase(k)))

function Base.write(dc::DataCollection)
    if isnothing(dc.path)
        throw(ArgumentError("No collection writer is provided, so an IO argument must be given."))
    end
    write(dc.path, dc)
end

Base.write(ds::DataSet) = write(ds.collection)
Base.write(adt::AbstractDataTransformer) = write(adt.dataset)
