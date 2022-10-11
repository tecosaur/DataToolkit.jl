QualifiedType(t::AbstractString) = parse(QualifiedType, t)

QualifiedType(m::Symbol, name::Symbol) = QualifiedType(m, name, ())

QualifiedType(::Type{T}) where {T} =
    QualifiedType(Symbol(parentmodule(T)), nameof(T),
                  if isconcretetype(T) Tuple(T.parameters) else () end)

QualifiedType(qt::QualifiedType) = qt

function Base.convert(::Type{Type}, qt::QualifiedType)
    try
        T = getfield(getfield(Main, qt.parentmodule), qt.name)
        if isempty(qt.parameters) T else
            tparams = map(qt.parameters) do p
                if p isa QualifiedType
                    convert(Type, p)
                else p end
            end
            T{tparams...}
        end
    catch e
        if !(e isa UndefVarError)
            rethrow(e)
        end
    end
end

function Base.issubset(a::QualifiedType, b::QualifiedType)
    if a == b
        true
    else
        A, B = convert(Type, a), convert(Type, b)
        !any(isnothing, (A, B)) && A <: B
    end
end

Base.issubset(a::QualifiedType, b::Type) = issubset(a, QualifiedType(b))
Base.issubset(a::Type, b::QualifiedType) = issubset(QualifiedType(a), b)
