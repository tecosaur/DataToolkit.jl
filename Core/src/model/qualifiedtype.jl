QualifiedType(m::Symbol, name::Symbol, params::Tuple=()) =
    QualifiedType(m, Symbol[], name, params)

QualifiedType(m::Symbol, parents::Vector{Symbol}, name::Symbol) =
    QualifiedType(m, parents, name, ())

function QualifiedType(::Type{T0}) where {T0}
    let qt = get(QUALIFIED_TYPE_CACHE, T0, nothing)
        !isnothing(qt) && return qt
    end
    T = Base.unwrap_unionall(T0)
    alias = Base.make_typealias(T)
    root, name, params = if isnothing(alias)
        parentmodule(T), nameof(T),
        map(p -> if p isa Type QualifiedType(p) else p end,
            T.parameters)
    else
        alias::Tuple{GlobalRef, Core.SimpleVector}
        first(alias).mod, first(alias).name,
        map(p -> if p isa Type QualifiedType(p) else p end,
            collect(last(alias)))
    end
    parents = Symbol[]
    while root != parentmodule(root) && root ∉ (Base, Core)
        push!(parents, nameof(root))
        root = parentmodule(root)
    end
    QUALIFIED_TYPE_CACHE[T0] =
        QualifiedType(nameof(root), parents, name, Tuple(params))
end

Base.:(==)(a::QualifiedType, b::QualifiedType) =
    a.root == b.root && a.parents == b.parents &&
    a.name == b.name && a.parameters == b.parameters

QualifiedType(qt::QualifiedType) = qt
QualifiedType(t::AbstractString) = parse(QualifiedType, t) # remove?

function Base.show(io::IO, ::MIME"text/plain", qt::QualifiedType)
    print(io, "QualifiedType(", string(qt), ")")
end

"""
    typeify(qt::QualifiedType; mod::Module=Main)

Convert `qt` to a `Type` available in `mod`, if possible.
If this cannot be done, `nothing` is returned instead.
"""
function typeify(qt::QualifiedType; mod::Module=Main, shoulderror::Bool=false)::Union{Type, Nothing}
    mod = if qt.root === :Main
        mod
    elseif isdefined(mod, qt.root)
        getfield(mod, qt.root)
    else
        hmod = nothing
        for (pkgid, pmod) in Base.loaded_modules
            if pkgid.name == String(qt.root)
                hmod = pmod
                break
            end
        end
        hmod
    end
    for parent in qt.parents
        mod = if isdefined(mod, parent)
            getfield(mod, parent)
        end
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
            foldl((t, p) -> UnionAll(p, t),
                  tparams[reverse(findall(@. tparams isa TypeVar))],
                  init = T{tparams...})
        else
            T{tparams...}
        end
    elseif shoulderror
        throw(ImpossibleTypeException(qt, mod))
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
        "DataSet" => QualifiedType(nameof(@__MODULE__), :DataSet),
        "DataFrame" => QualifiedType(:DataFrames, :DataFrame))
    (; forward, reverse = Dict(val => key for (key, val) in forward))
end
