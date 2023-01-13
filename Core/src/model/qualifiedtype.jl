QualifiedType(t::AbstractString) = parse(QualifiedType, t)

QualifiedType(m::Symbol, name::Symbol) = QualifiedType(m, name, ())

QualifiedType(::Type{T}) where {T} = let T = Base.unwrap_unionall(T)
    QualifiedType(Symbol(parentmodule(T)), nameof(T),
                  if T isa DataType Tuple(T.parameters) else () end)
end

QualifiedType(qt::QualifiedType) = qt

function Base.convert(::Type{Type}, qt::QualifiedType; mod::Module=Main)
    mod = if qt.parentmodule === :Main
        mod
    elseif isdefined(mod, qt.parentmodule)
        getfield(mod, qt.parentmodule)
    else
        hmod = Some(nothing)
        for (pkgid, pmod) in Base.loaded_modules
            if pkgid.name == String(qt.parentmodule)
                hmod = pmod
                break
            end
        end
        hmod
    end
    # For the sake of the `catch` statement:
    if !isnothing(mod) && isdefined(mod, qt.name)
        T = getfield(mod, qt.name)
        if isempty(qt.parameters) T else
            tparams = map(qt.parameters) do p
                if p isa QualifiedType
                    convert(Type, p; mod)
                else p end
            end
            if any(@. tparams isa TypeVar)
                UnionAll(tparams[findfirst(@. tparams isa TypeVar)],
                         T{tparams...})
            else
                T{tparams...}
            end
        end
    end
end

function Base.issubset(a::QualifiedType, b::QualifiedType; mod::Module=Main)
    if a == b
        true
    else
        A, B = convert(Type, a; mod), convert(Type, b; mod)
        !any(isnothing, (A, B)) && A <: B
    end
end

Base.issubset(a::QualifiedType, b::Type; mod::Module=Main) =
    issubset(a, QualifiedType(b); mod)
Base.issubset(a::Type, b::QualifiedType; mod::Module=Main) =
    issubset(QualifiedType(a), b; mod)

# For the sake of convenience when parsing(foward)/writing(reverse).
const QUALIFIED_TYPE_SHORTHANDS = let forward =
    Dict{String, QualifiedType}(
        "FilePath" => QualifiedType(FilePath),
        "DataFrame" => QualifiedType(:DataFrames, :DataFrame))
    (; forward, reverse = Dict(val => key for (key, val) in forward))
end
