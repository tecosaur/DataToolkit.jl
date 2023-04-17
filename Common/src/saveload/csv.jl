function load(loader::DataLoader{:csv}, from::IO, sink::Type)
    @import CSV
    kwargs = Dict{Symbol, Any}(
        Symbol(k) => v for (k, v) in get(loader, "args", Dict{String, Any}()))
    if haskey(kwargs, :types)
        kwargs[:types] = typeify.(QualifiedType.(kwargs[:types]))
    end
    if haskey(kwargs, :typemap)
        kwargs[:typemap] = Dict{Type, Type}(
            typeify(QualifiedType(k)) => typeify(QualifiedType(v))
            for (k, v) in kwargs[:typemap])
    end
    if haskey(kwargs, :stringtype)
        kwargs[:stringtype] = typeify.(QualifiedType.(kwargs[:stringtype]))
    end
    CSV.File(from; NamedTuple(kwargs)...) |>
        if sink == Any || sink == CSV.File
            identity
        elseif QualifiedType(sink) == QualifiedType(:DataFrames, :DataFrame)
            # Replace `SentinelArray.ChainedVector` columns with standard vectors.
            csv -> let df = sink(csv)
                for (i, col) in enumerate(getfield(df, :columns))
                    getfield(df, :columns)[i] = Array(col)
                end
                df
            end
        elseif sink == Matrix
            Tables.matrix
        else
            sink
        end
end

supportedtypes(::Type{DataLoader{:csv}}) =
    [QualifiedType(:DataFrames, :DataFrame),
     QualifiedType(:Base, :Matrix),
     QualifiedType(:CSV, :File)]

function save(writer::DataWriter{:csv}, dest::IO, info)
    @import CSV
    kwargs = Dict(Symbol(k) => v for (k, v) in
                      get(writer, "args", Dict{String, Any}()))
    for charkey in (:quotechar, :openquotechar, :escapechar)
        if haskey(kwargs, charkey)
            kwargs[charkey] = first(kwargs[charkey])
        end
    end
    CSV.write(dest, info; NamedTuple(kwargs)...)
end

createpriority(::Type{DataLoader{:csv}}) = 10

function create(::Type{DataLoader{:csv}}, source::String)
    if !isnothing(match(r"\.[ct]sv$"i, source))
        Dict{String, Any}()
    end
end
