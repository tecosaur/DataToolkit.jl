"""
    iswritable(dc::DataCollection)
Check whether a data collection is backed by a writable file.
"""
Base.iswritable(dc::DataCollection) =
    !isnothing(dc.path) &&
    get(dc, "locked", false) !== true &&
    try # why is this such a hassle?
        open(io -> iswritable(io), dc.path, "a")
    catch e
        if e isa SystemError
            false
        else
            rethrow(e)
        end
    end

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
            elseif p isa TypeVar
                string(p.name, "<:", string(p.ub))
            else
                string(p)
            end
        end
        string(qname, '{', join(parstr, ','), '}')
    end
end

function Base.convert(::Type{Dict}, adt::AbstractDataTransformer)
    adt.dataset.collection.advise(tospec, adt)
end

function tospec(adt::AbstractDataTransformer)
    merge(Dict("driver" => string(first(typeof(adt).parameters)),
               "type" => if length(adt.type) == 1
                   string(first(adt.type))
               else
                   string.(adt.type)
               end,
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

"""
    natkeygen(key::String)
Generate a sorting key for `key` that when used with `sort` will put the
collection in "natural order".

```julia-repl
julia> sort(["A1", "A10", "A02", "A1.5"], by=natkeygen)
4-element Vector{String}:
 "A1"
 "A1.5"
 "A02"
 "A10"
```
"""
function natkeygen(key::String)
    map(eachmatch(r"(\d*\.\d+)|(\d+)|([^\d]+)", lowercase(key))) do (; captures)
        float, int, str = captures
        if !isnothing(float)
            f = parse(Float64, float)
            fint, dec = floor(Int, f), mod(f, 1)
            '0' * Char(fint) * string(dec)[3:end]
        elseif !isnothing(int)
            '0' * Char(parse(Int, int))
        else
            str
        end
    end
end

function Base.write(io::IO, dc::DataCollection)
    datakeygen(key) = if haskey(DATA_CONFIG_KEY_SORT_MAPPING, key)
        [DATA_CONFIG_KEY_SORT_MAPPING[key]]
    else
        natkeygen(key)
    end
    TOML.print(io, filter(((_, value),) -> !isnothing(value) && !isempty(value),
                          convert(Dict, dc));
               sorted = true, by = datakeygen)
end

function Base.write(dc::DataCollection)
    if !iswritable(dc)
        if !isnothing(dc.path)
            throw(ArgumentError("No collection writer is provided, so an IO argument must be given."))
        else
            throw(SystemError("Data collection is not writable"))
        end
    end
    write(dc.path, dc)
end

Base.write(ds::DataSet) = write(ds.collection)
Base.write(adt::AbstractDataTransformer) = write(adt.dataset)
