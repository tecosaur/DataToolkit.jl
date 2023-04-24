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
    @advise tospec(adt)
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
    @advise tospec(ds)
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
    @advise tospec(dc)
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
    tomlreformat!(io::IO)

Consume `io` representing a TOML file, and reformat it to improve readability.
Currently this takes the form of the following changes:
- Replace inline multi-line strings with multi-line toml strings.

An IOBuffer containing the reformatted content is returned.

The processing assumes that `io` contains `TOML.print`-formatted content.
Should this not be the case, mangled TOML may be emitted.
"""
function tomlreformat!(io::IO)
    out = IOBuffer()
    bytesavailable(io) == 0 && seekstart(io)
    for line in eachline(io)
        # Check for multi-line candidates. Cases:
        #  1. key = "string..."
        #  2. 'key...' = "string..."
        #  3. "key..." = "string..."
        if !isnothing(match(r"^\s*(?:[A-Za-z0-9_-]+|\'[ \"A-Za-z0-9_-]+\'|\"[ 'A-Za-z0-9_-]+\") *= * \".*\"$", line))
            write(out, line[1:findfirst(!isspace, line)-1]) # apply indent
            key, value = first(TOML.parse(line))
            if length(value) < 40 || count('\n', value) == 0 || (count('\n', value) < 3 && length(value) < 90)
                TOML.print(out, Dict{String, Any}(key => value))
            elseif !occursin("'''", value) && count('"', value) > 4 &&
                !any(c -> c != '\n' && Base.iscntrl(c), value)
                TOML.Internals.Printer.printkey(out, [key])
                write(out, " = '''\n", value, "'''\n")
            else
                TOML.Internals.Printer.printkey(out, [key])
                write(out, " = \"\"\"\n",
                      replace(sprint(TOML.Internals.Printer.print_toml_escaped, value),
                              "\\n" => '\n'),
                      "\"\"\"\n")
            end
        else
            write(out, line, '\n')
        end
    end
    out
end

function Base.write(io::IO, dc::DataCollection)
    datakeygen(key) = if haskey(DATA_CONFIG_KEY_SORT_MAPPING, key)
        [DATA_CONFIG_KEY_SORT_MAPPING[key]]
    else
        natkeygen(key)
    end
    intermediate = IOBuffer()
    TOML.print(intermediate,
               filter(((_, value),) -> !isnothing(value) && !isempty(value),
                      convert(Dict, dc));
               sorted = true, by = datakeygen)
    write(io, take!(tomlreformat!(intermediate)))
end

function Base.write(dc::DataCollection)
    if !iswritable(dc)
        if !isnothing(dc.path)
            throw(ArgumentError("No collection writer is provided, so an IO argument must be given."))
        else
            throw(ReadonlyCollection(dc))
        end
    end
    write(dc.path, dc)
end

Base.write(ds::DataSet) = write(ds.collection)
Base.write(adt::AbstractDataTransformer) = write(adt.dataset)
