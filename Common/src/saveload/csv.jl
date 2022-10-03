function load(loader::DataLoader{:csv}, from::IO, sink::Type)
    @use CSV
    kwargs = Dict(Symbol(k) => v for (k, v) in
                      get(loader, "args", Dict{String, Any}()))
    if haskey(kwargs, :types)
        kwargs[:types] = convert.(Type, QualifiedType.(kwargs[:types]))
    end
    if haskey(kwargs, :typemap)
        kwargs[:typemap] = Dict{Type, Type}(
            convert(Type, QualifiedType(k)) => convert(Type, QualifiedType(v))
            for (k, v) in kwargs[:typemap])
    end
    if haskey(kwargs, :stringtype)
        kwargs[:stringtype] = convert.(Type, QualifiedType.(kwargs[:stringtype]))
    end
    CSV.File(from; NamedTuple(kwargs)...) |> if sink != Any
        sink else identity end
end

supportedtypes(::Type{DataLoader{:csv}}) =
    [QualifiedType(:DataFrames, :DataFrame),
     QualifiedType(:Base, :Matrix),
     QualifiedType(:CSV, :File)]

function save(writer::DataWriter{:csv}, dest::IO, info)
    @use CSV
    kwargs = Dict(Symbol(k) => v for (k, v) in
                      get(writer, "args", Dict{String, Any}()))
    for charkey in (:quotechar, :openquotechar, :escapechar)
        if haskey(kwargs, charkey)
            kwargs[charkey] = first(kwargs[charkey])
        end
    end
    CSV.write(dest, info; NamedTuple(kwargs)...)
end
