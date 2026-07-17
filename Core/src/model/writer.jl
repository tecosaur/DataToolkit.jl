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


# Batch writing

"""
    WriteRecord

A record of write statistics and scheduling for each `DataCollection` written.

## Structure

- `write`:
    - `last::Float64`: The time of the last write.
    - `duration::Float64`: The duration of the last write performed.
    - `count::Int`: The number of writes performed.
- `invoke`:
    - `last::Float64`: The time of the last invocation of `save!`.
    - `count::Int`: The number of times `save!` was invoked.
- `queued::Bool`: Whether a write is queued for later execution.
"""
struct WriteRecord
    invoke::@NamedTuple{last::Float64, count::Int}
    write::@NamedTuple{last::Float64, duration::Float64, count::Int}
    queued::Bool
end

const BLANK_WRITE_RECORD =
    WriteRecord((last = 0.0, count = 0),
                (last = 0.0, duration = 0.0, count = 0),
                false)

"""
    WRITE_RECORDS

A record of write statistics and scheduling for each `DataCollection` written.

The record is a `WeakKeyDict` mapping `DataCollection` objects to
`WriteRecord` objects. This is used to track the timing of writes
an to schedule writes in a debounced manner.

See also: `save!`, `writesoon`, `WriteRecord`, `WRITE_DEBOUNCE_FACTOR`, `WRITE_DEFER_LIMIT`.
"""
const WRITE_RECORDS = WeakKeyDict{DataCollection, WriteRecord}()

"""
    WRITE_DEBOUNCE_FACTOR

How long the dynamic debounce duration should be,
as a multiple of the last write duration.

See also: `WRITE_DEFER_LIMIT`.
"""
const WRITE_DEBOUNCE_FACTOR = 4

"""
    WRITE_DEFER_LIMIT

The maximum number of intervals of the debounce duration
to wait before performing a write.

See also: `WRITE_DEBOUNCE_FACTOR`.
"""
const WRITE_DEFER_LIMIT = 12

"""
    save!(dc::DataCollection)

Save the `DataCollection` `dc` to its source file.

The `DataCollection` must be backed by a file, and the file must be writable.

The `save!` operation is debounced and asynchronous to prevent
serialisation time from dominating in large write-heavy scenarios.
"""
function save!(dc::DataCollection)
    if !iswritable(dc)
        if isnothing(dc.source)
            throw(ArgumentError("The collection is not backed by a file, and so cannot be saved."))
        else
            throw(ReadonlyCollection(dc))
        end
    end
    lock(WRITE_RECORDS)
    record = get(WRITE_RECORDS, dc, BLANK_WRITE_RECORD)
    if record.queued
        newinvoke = (last = time(), count = record.invoke.count + 1)
        WRITE_RECORDS[dc] = WriteRecord(newinvoke, record.write, record.queued)
        unlock(WRITE_RECORDS)
    elseif time() - record.invoke.last > WRITE_DEBOUNCE_FACTOR * record.write.duration
        start = time()
        WRITE_RECORDS[dc] = WriteRecord((last = start, count = record.invoke.count + 1),
                                        record.write, true)
        unlock(WRITE_RECORDS)
        try
            atomic_write(dc.source.path, dc)
            duration = time() - start
            @lock WRITE_RECORDS let
                record = get(WRITE_RECORDS, dc, BLANK_WRITE_RECORD)
                WRITE_RECORDS[dc] = WriteRecord(
                    record.invoke,
                    (last = start, duration = duration, count = record.write.count + 1),
                    false)
            end
        catch
            @lock WRITE_RECORDS let
                record = get(WRITE_RECORDS, dc, BLANK_WRITE_RECORD)
                WRITE_RECORDS[dc] = WriteRecord(record.invoke, record.write, false)
            end
            rethrow()
        end
    else
        WRITE_RECORDS[dc] = WriteRecord(record.invoke, record.write, true)
        unlock(WRITE_RECORDS)
        @spawn writesoon(dc)
    end
    dc
end

save!(ds::DataSet) = save!(ds.collection)
save!(dt::DataTransformer) = save!(dt.dataset)

"""
    writesoon(dc::DataCollection)

Schedule a write for `dc`.

This is used to perform a debounced write of the `DataCollection`
after a delay. The delay is determined by the `WRITE_DEBOUNCE_FACTOR`
and the last write duration. The function will wait for a maximum
of `WRITE_DEFER_LIMIT` intervals of the debounce duration before
performing the write.

It is assumed that the `.queued` field of the `WriteRecord` is set to `true`
immediately before this function is called. Otherwise, this function will return
immediately without performing any action.
"""
function writesoon(dc::DataCollection)
    debounce = let irecord = get(WRITE_RECORDS, dc, BLANK_WRITE_RECORD)
        irecord.queued || return
        WRITE_DEBOUNCE_FACTOR * irecord.write.duration
    end
    for _ in 1:WRITE_DEFER_LIMIT
        sleep(debounce)
        crecord = get(WRITE_RECORDS, dc, BLANK_WRITE_RECORD)
        crecord.queued || return
        if time() - crecord.invoke.last >= debounce
            break
        end
    end
    record = get(WRITE_RECORDS, dc, BLANK_WRITE_RECORD)
    record.queued || return
    try
        writestart = time()
        atomic_write(dc.source.path, dc)
        writeduration = time() - writestart
        @lock WRITE_RECORDS let
            record = get(WRITE_RECORDS, dc, BLANK_WRITE_RECORD)
            newwrite = (last = writestart,
                        duration = writeduration,
                        count = record.write.count + 1)
            WRITE_RECORDS[dc] = WriteRecord(record.invoke, newwrite, false)
        end
    catch
        @lock WRITE_RECORDS let
            record = get(WRITE_RECORDS, dc, BLANK_WRITE_RECORD)
            WRITE_RECORDS[dc] = WriteRecord(record.invoke, record.write, false)
        end
        rethrow()
    end
    nothing
end

"""
    flushpendingwrites()

Perform all pending data collection writes in the `WRITE_RECORDS` dictionary.
"""
function flushpendingwrites()
    @lock WRITE_RECORDS begin
        for (dc, record) in WRITE_RECORDS
            record.queued || continue
            atomic_write(dc.source.path, dc)
        end
        empty!(WRITE_RECORDS)
    end
end
