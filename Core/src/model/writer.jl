"""
    iswritable(dc::DataCollection)

Check whether the data collection `dc` is backed by a writable file.
"""
function Base.iswritable(dc::DataCollection)
    !isnothing(dc.source) || return false
    get(dc, "locked", false) !== true || return false
    @static if VERSION >= v"1.11"
        if isfile(dc.source.path)
            iswritable(dc.source.path)
        else
            iswritable(dirname(dc.source.path))
        end
    else
        try # why is this such a hassle?
            open(io -> iswritable(io), dc.source.path, "a")
        catch e
            if e isa SystemError
                false
            else
                rethrow()
            end
        end
    end
end

function Base.string(q::QualifiedType)
    if haskey(QUALIFIED_TYPE_SHORTHANDS.reverse, q)
        return QUALIFIED_TYPE_SHORTHANDS.reverse[q]
    end
    qname = if q.root == :Base && Base.isexported(Base, q.name)
        string(q.name)
    elseif q.root == :Core && Base.isexported(Core, q.name)
        string(q.name)
    elseif isempty(q.parents)
        string(q.root, '.', q.name)
    else
        string(q.root, '.', join(q.parents, '.'), '.', q.name)
    end
    if isempty(q.parameters)
        qname
    else
        parstr = map(q.parameters) do p
            if p isa Symbol
                string(':', p)
            elseif p isa TypeVar
                string(ifelse(first(String(p.name)) == '#',
                              "", String(p.name)),
                       "<:", string(p.ub))
            else
                string(p)
            end
        end
        string(qname, '{', join(parstr, ','), '}')
    end
end

Base.convert(::Type{Dict}, dt::DataTransformer) = @advise tospec(dt)

"""
    tospec(thing::DataTransformer)
    tospec(thing::DataSet)
    tospec(thing::DataCollection)

Return a `Dict` representation of `thing` for writing as TOML.
"""
function tospec(dt::DataTransformer)
    function drivername(::DataTransformer{_kind, D}) where {_kind, D}
        @nospecialize
        D
    end
    merge(Dict{String, Any}(
        "driver" => string(drivername(dt)),
        "type" => if length(dt.type) == 1
            string(first(dt.type))
        else
            map(string, dt.type)
        end,
        "priority" => dt.priority),
          dataset_parameters(dt.dataset, Val(:encode), dt.parameters))
end

Base.convert(::Type{Dict}, ds::DataSet) = @advise tospec(ds)

# Documented above
function tospec(ds::DataSet)
    attrs = Pair{String, Any}[
        "uuid" => string(ds.uuid),
        "storage" => map(s -> convert(Dict, s), ds.storage),
        "loader" => map(l -> convert(Dict, l), ds.loaders),
        "writer" => map(w -> convert(Dict, w), ds.writers)]
    filter!(p -> !isempty(last(p)), attrs)
    merge(Dict{String, Any}(attrs),
          dataset_parameters(ds, Val(:encode), ds.parameters))
end

Base.convert(::Type{Dict}, dc::DataCollection) = @advise tospec(dc)

function tospec(dc::DataCollection)
    datasets = Dict{String, Any}()
    for ds in dc.datasets
        if haskey(datasets, ds.name)
            push!(datasets[ds.name], convert(Dict, ds))
        else
            datasets[ds.name] = [convert(Dict, ds)]
        end
    end
    spec = Dict{String, Any}(
        "data_config_version" => dc.version,
        "name" => dc.name,
        "uuid" => string(dc.uuid),
        "plugins" => dc.plugins,
        "config" => dataset_parameters(dc, Val(:encode), dc.parameters))
    merge(datasets, spec)
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
            write(out, line[1:something(findfirst(!isspace, line),1)-1]) # apply indent
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
        if !isnothing(dc.source.path)
            throw(ArgumentError("No collection writer is provided, so an IO argument must be given."))
        else
            throw(ReadonlyCollection(dc))
        end
    end
    nb = atomic_write(dc.source.path, dc)
    dc.source = (; path = dc.source.path, mtime = mtime(dc.source.path))
    nb
end

Base.write(ds::DataSet) = write(ds.collection)
Base.write(dt::DataTransformer) = write(dt.dataset)
