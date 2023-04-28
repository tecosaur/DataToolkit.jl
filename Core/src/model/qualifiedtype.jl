QualifiedType(t::AbstractString) = parse(QualifiedType, t)

QualifiedType(m::Symbol, name::Symbol) = QualifiedType(m, name, ())

function QualifiedType(::Type{T_}) where {T_}
    T = Base.unwrap_unionall(T_)
    params = map(p -> if p isa Type
                     QualifiedType(p)
                 else p end,
                 T.parameters)
    QualifiedType(Symbol(parentmodule(T)), nameof(T), Tuple(params))
end

QualifiedType(qt::QualifiedType) = qt

"""
    typeify(qt::QualifiedType; mod::Module=Main)

Convert `qt` to a `Type` availible in `mod`, if possible.
If this cannot be done, `nothing` is returned instead.
"""
function typeify(qt::QualifiedType; mod::Module=Main)
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
        isempty(qt.parameters) && return T
        tparams = map(qt.parameters) do p
            if p isa QualifiedType
                typeify(p; mod)
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

function Base.issubset(a::QualifiedType, b::QualifiedType; mod::Module=Main)
    if a == b
        true
    else
        A, B = typeify(a; mod), typeify(b; mod)
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
        "DataSet" => QualifiedType(Symbol(@__MODULE__), :DataSet),
        "DataFrame" => QualifiedType(:DataFrames, :DataFrame))
    (; forward, reverse = Dict(val => key for (key, val) in forward))
end
