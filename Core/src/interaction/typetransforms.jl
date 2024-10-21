## Type transformations

# This is essentially the infrastructure for dynamic dispatch on steroids (`read1`).
#
# I'm aware that this use of `methods` and direct accessing of signatures looks
# somewhat iffy. However, I'm not aware of any alternative approach that is able
# to achieve the level of dynamism or ease of use that we're trying to produce
# here — short of perhaps explicitly registering methods somehow, but to me that
# approach seems to suffer from distinctly inferior ease of use.
#
# By determining all the possible type transformation the defined methods of a
# data transformer might be able to perform, given a target output type, we can
# then consider the possibilities of multiple stages of transformation together
# in concert.

"""
    issubtype(X::Type, T::Union{Type, TypeVar})
    issubtype(x::X, T::Union{Type, TypeVar})

Check if `X` is indeed a subtype of `T`.

This is a tweaked version of `isa` that can (mostly) handle `TypeVar` instances.
"""
function issubtype(X::Type, T::Union{Type, TypeVar})
    if T isa TypeVar
        # We can't really handle complex `TypeVar` situations,
        # but we'll give the very most basic a shot, and cross
        # our fingers with the rest.
        if T.lb isa Type && T.ub isa Type
            T.lb <: X <: T.ub
        else
            false
        end
    else
        X <: T
    end
end

issubtype(x, T::Union{Type, TypeVar}) =
    issubtype(typeof(x), T::Union{Type, TypeVar})

"""
    paramtypebound(T::Union{Type, TypeVar}, Tparam::Union{Type, TypeVar}, paramT::Type)

Return the `Type` that bounds `T`.

This is simply `T` when `T` isa `Type`, but `T` may also be a `TypeVar` that is
parameterised by `Tparam`. In this case, the `Type` that `T` is parameterised by
is returned, which is taken to be `paramT`.

Given a type `T` that may be parameterised according to `Tparam`,

```julia-repl
julia> paramtypebound(String, IO, IO)
String

julia> T = TypeVar(:T)
T

julia> paramtypebound(T, Type{T}, Float64)
Float64
```
"""
function paramtypebound(T::Union{Type, TypeVar}, Tparam::Union{Type, TypeVar}, paramT::Type)
    if T isa TypeVar && Type{T} == Tparam
        paramT
    elseif T isa TypeVar
        T.ub
    else
        T
    end::Type
end

"""
    targettypes(types::Vector{QualifiedType}, desired::Type) -> Vector{Type}
    targettypes(transformer::DataTransformer, desired::Type) -> Vector{Type}

Return all `Type`s that one might hope to produce from `types` or `transformer`.

More specifically, this will give all `Type`s that can be produced which are a
subtype of `desired`, and `desired` itself.

Priority order is preserved.
"""
function targettypes end

function targettypes(types::Vector{QualifiedType}, desired::Type; mod::Module = Main)
    @nospecialize
    targets = Type[]
    for typ in types
        Ttyp = typeify(typ; mod)
        isnothing(Ttyp) && continue
        if Ttyp <: desired
            push!(targets, Ttyp)
        end
    end
    targets
end

targettypes(@nospecialize(storage::DataStorage), @nospecialize(desired::Type)) =
    targettypes(storage.type, desired; mod=storage.dataset.collection.mod)

targettypes(@nospecialize(loader::DataLoader), @nospecialize(desired::Type)) =
    targettypes(loader.type, desired; mod=loader.dataset.collection.mod)

targettypes(@nospecialize(writer::DataWriter), @nospecialize(desired::Type)) =
    targettypes(writer.type, desired; mod=writer.dataset.collection.mod)

"""
    ispreferredpath(a, b)

Compares two "type paths" `a` and `b`, returning whether
`a` is preferred.

Each "type path" is a tuple of the form:

    (Tin::Type => Tout::Type, index::Int, transformer::Type{<:DataTransformer})

This operates on the following rules:
1. The path with the lower index is preferred.
2. If the indices are equal, the path with the more specific output type is preferred.
3. If the output types are equally specific, the path with the more specific loader is preferred.
4. If the loaders are equally specific, the more similar data transformation (`Tin => Tout`) is preferred.
"""
function ispreferredpath(((a_in, a_out), a_ind, a_ldr)::Tuple{Pair{Type, Type}, Int, Type},
                         ((b_in, b_out), b_ind, b_ldr)::Tuple{Pair{Type, Type}, Int, Type})
    function ncommonparents(A::Type, B::Type)::Int
        a_parents, b_parents = Type[A], Type[B]
        while first(a_parents) != Any
            pushfirst!(a_parents, supertype(first(a_parents)))
        end
        while first(b_parents) != Any
            pushfirst!(b_parents, supertype(first(b_parents)))
        end
        sum(splat(==), zip(a_parents, b_parents))
    end
    @nospecialize
    a_ind < b_ind ||
        Base.morespecific(a_out, b_out) ||
        Base.morespecific(a_ldr, b_ldr) ||
        ncommonparents(a_in, a_out) > ncommonparents(b_in, b_out)
end

"""
    transformersigs(transformer::Type{<:DataTransformer}, desired::Type)

Return processed signatures of the transformation methods implemented for
`transformer` that could produce/provide a subtype of `desired`.

- `DataStorage` produces tuples of `(Type{<:DataStorage}, Type{out})`
- `DataLoaders` produces tuples of `(Type{<:DataLoader}, Type{in}, Type{out})`
- `DataWriter` produces tuples of `(Type{<:DataWriter}, Type{in}, Type{data})`

The `DataStorage` method takes a `write::Bool` keyword argument.
"""
function transformersigs end

"""
    typevariants(T::Type) -> Vector{Tuple{Type, Bool}}

Break a type `T` down into all types that its composed of, and indicate subtypeability.
"""
function typevariants(T::Type)::Vector{Tuple{Type, Bool}}
    if T == Type || T == Any
        [(Any, false)]
    elseif T isa UnionAll && T.var.ub isa Union
        [(Tu, true) for (Tu, _) in
             first(Base.unwrap_unionall(T).parameters).ub |> typevariants]
    elseif T isa UnionAll || (T isa DataType && T.name.name != :Type)
        [(T, false)]
    elseif T isa Union
        Ta = Tuple{Type, Bool}[]
        for Tu in Base.uniontypes(T)
            append!(Ta, typevariants(Tu))
        end
        Ta
    elseif T isa Type{<:Any}
        typevariants(first(T.parameters))
    else
        [(T, false)]
    end
end

typevariants(T::TypeVar) = [(Tu, true) for (Tu, _) in typevariants(T.ub)]

function transformersigs(S::Type{<:DataStorage}, desired::Type; read::Bool=true, write::Bool=true)
    @nospecialize
    ms = Vector{Method}(methods(storage, Tuple{DataStorage, <:Any}).ms)
    read && append!(ms, methods(getstorage, Tuple{DataStorage, <:Any}).ms)
    write && append!(ms, methods(putstorage, Tuple{DataStorage, <:Any}).ms)
    sort!(ms, by = m -> m.primary_world)
    sigs = [Base.unwrap_unionall(m.sig) for m in ms]
    types = Tuple{Type, Union{Type, TypeVar}}[]
    for sig in sigs
        (_, Tstor::Union{Type, TypeVar}, Tout1::Type) = sig.types
        Tstor == DataStorage && Tout1 in (Any, Type) && continue
        issubtype(S, Tstor) || continue
        if Tstor isa TypeVar
            Tstor = Tstor.ub
        end
        if Tout1 == Type
            push!(types, (Tstor, desired))
        else
            for (Tout, cansubtype) in typevariants(Tout1)
                Tout <: desired || desired <: Tout || continue
                push!(types, (Tstor, ifelse(cansubtype, desired, Tout)))
            end
        end
    end
    types
end

function transformersigs(L::Type{<:DataLoader}, desired::Type)
    @nospecialize
    ms = methods(load, Tuple{DataLoader, <:Any, <:Any}).ms
    sort!(ms, by = m -> m.primary_world)
    sigs = [Base.unwrap_unionall(m.sig) for m in ms]
    types = Tuple{Type, Union{Type, TypeVar}, Type}[]
    for sig in sigs
        (_, Tloader::Union{Type, TypeVar}, Tin::Union{Type, TypeVar}, Tout1::Type) = sig.types
        issubtype(L, Tloader) || continue
        if Tloader isa TypeVar
            Tloader = Tloader.ub
        end
        if Tout1 == Type{Tin} && (Tin isa TypeVar || Tout1 == Type)
            push!(types, (Tloader, desired, desired))
        else
            for (Tout, cansubtype) in typevariants(Tout1)
                Tout <: desired || desired <: Tout || continue
                push!(types, (Tloader, Tin, ifelse(cansubtype, desired, Tout)))
            end
        end
    end
    types
end

function transformersigs(W::Type{<:DataWriter}, desired::Type)
    @nospecialize
    ms = methods(save, Tuple{DataWriter, <:Any, <:Any}).ms
    sort!(ms, by = m -> m.primary_world)
    sigs = [Base.unwrap_unionall(m.sig) for m in ms]
    types = Tuple{Type, Union{Type, TypeVar}, Type}[]
    for sig in sigs
        (_, Twriter::Union{Type, TypeVar}, Tdest::Union{Type, TypeVar}, Tin1::Type) = sig.types
        issubtype(W, Twriter) || continue
        if Twriter isa TypeVar
            Twriter = Twriter.ub
        end
        if Tin1 == Type
            push!(types, (Twriter, Tdest, desired))
        else
            for (Tin, cansubtype) in typevariants(Tin1)
                issubtype(Tin, desired) || continue
                push!(types, (Twriter, Tdest, ifelse(cansubtype, desired, Tin)))
            end
        end
    end
    types
end

supportedtypes(S::Type{<:DataStorage}, T::Type=Any)::Vector{QualifiedType} =
    map(QualifiedType, map(last, transformersigs(S, T)) |> unique |> reverse)

supportedtypes(L::Type{<:DataLoader}, T::Type=Any)::Vector{QualifiedType} =
    map(QualifiedType, map(last, transformersigs(L, T)) |> unique |> reverse)

supportedtypes(W::Type{<:DataWriter}, T::Type=Any)::Vector{QualifiedType} =
    map(QualifiedType, map(s -> s[2], transformersigs(W, T)) |> unique |> reverse)

"""
    typesteps(loader::DataLoader, desired::Type) -> Vector{Pair{Type, Type}}

Identify and order all uses of `loader` that may produce a subtype of `desired`.

More specifically, this finds all `load` methods that can produce a subtype of
`desired`, checks what input and output types they work with, and orders them
according to the declared types of `loader` and the specificity of the output
types (more specific is interpreted as better).

The output vector gives the step-change in the type domain that each method performs.
"""
function typesteps end

function typesteps(loader::DataLoader, desired::Type)
    @nospecialize
    target_types = targettypes(loader, desired)
    desired in target_types || push!(target_types, desired)
    path_infos = Tuple{Pair{Type, Type}, Int, Type}[]
    for (Tloader, Tin, Tout) in transformersigs(typeof(loader), desired)
        if Tout isa TypeVar || Tout == Any
            for ttype in target_types
                intype = paramtypebound(Tin, Tout, ttype)
                target_ind = something(findfirst(qt -> qt <: ttype, target_types),
                                       length(target_types) + 1)
                push!(path_infos, ((intype => ttype), target_ind, Tloader))
            end
        else
            intype = paramtypebound(Tin, Tout, desired)
            target_ind = something(findfirst(qt -> qt <: Tout, target_types),
                                   length(target_types) + 1)
            push!(path_infos, ((intype => Tout), target_ind, Tloader))
        end
    end
    sort!(path_infos, lt = ispreferredpath)
    unique(map(first, path_infos))
end

function typesteps(store::DataStorage, desired::Type; write::Bool)
    @nospecialize
    target_types = targettypes(store, desired)
    desired in target_types || push!(target_types, desired)
    path_infos = Tuple{Pair{Type, Type}, Int, Type}[]
    for (Tstor, Tout) in transformersigs(typeof(store), desired; read=!write, write)
        if Tout isa TypeVar || Tout == Any
            for ttype in target_types
                target_ind = something(findfirst(qt -> qt <: Tout, target_types),
                                       length(target_types) + 1)
                push!(path_infos, ((Nothing => ttype), target_ind, Tstor))
            end
        else
            target_ind = something(findfirst(qt -> qt <: Tout, target_types),
                                   length(target_types) + 1)
            push!(path_infos, ((Nothing => Tout), target_ind, Tstor))
        end
    end
    sort!(path_infos, lt = ispreferredpath)
    unique(map(first, path_infos))
end

function typesteps(writer::DataWriter, desired::Type)
    @nospecialize
    target_types = targettypes(writer, desired)
    desired in target_types || push!(target_types, desired)
    path_infos = Tuple{Pair{Type, Type}, Int, Type}[]
    for (Twriter, Tdest, Tin) in transformersigs(typeof(writer), desired)
        if Tin isa TypeVar || Tin == Any
            for ttype in target_types
                desttype = paramtypebound(Tdest, Tin, ttype)
                target_ind = something(findfirst(qt -> qt <: ttype, target_types),
                                       length(target_types) + 1)
                push!(path_infos, ((ttype => desttype), target_ind, Twriter))
            end
        else
            desttype = paramtypebound(Tdest, Tin, desired)
            target_ind = something(findfirst(qt -> qt <: Tin, target_types),
                                   length(target_types) + 1)
            push!(path_infos, ((Tin => desttype), target_ind, Twriter))
        end
    end
    sort!(path_infos, lt = ispreferredpath)
    unique(map(first, path_infos))
end

