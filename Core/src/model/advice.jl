DataAdvice(f::Function) =
    DataAdvice(DEFAULT_DATA_ADVISOR_PRIORITY, f)

Base.methods(dt::DataAdvice) = methods(dt.f)

# Abstract-y `typeof`.
atypeof(val) = if val isa Type
    Type{val}
else
    typeof(val)
end

# NOTE trying to express the type of keyword arguments and the
# zero-value form is surprisingly annoying once you want to support
# more than one Julia version. It's fine in v1.7+, but v1.6 is a bit
# fiddlier.
const _KWARGS_TYPE, _KWARGS_0 = if VERSION >= v"1.7"
    pairs(NamedTuple),
    Base.Pairs{Symbol, Union{}, Tuple{}, NamedTuple{(), Tuple{}}}(NamedTuple(),())
else
    let kw0 = ((; k...) -> k)()
        kwN = Base.Iterators.Pairs{Symbol, V, Tuple{Vararg{Symbol, N}}, NamedTuple{names, T}} where {V, N, names, T<:Tuple{Vararg{Any, N}}}
        Union{typeof(kw0), <:kwN}, kw0
    end
end

function (dt::DataAdvice{C, F})(
    (post, func, args, kwargs)::Tuple{Function, Function, Tuple, _KWARGS_TYPE};
    invokelatest::Bool=false) where {C, F}
    # @info "Testing $dt"
    kwkeys = getfield(kwargs, :itr) # `keys(kwargs)` works in 1.7+
    if hasmethod(dt.f, Tuple{typeof(post), typeof(func), atypeof.(args)...}, kwkeys)
        # @info "Applying $dt"
        try
            result = if invokelatest
                Base.invokelatest(df.f, post, func, args...; kwargs...)
            else
                dt.f(post, func, args...; kwargs...)
            end
            if result isa Tuple{Function, Function, Tuple}
                post, func, args = result
                (post, func, args, _KWARGS_0)
            else
                result
            end
        catch e
            if e isa PkgRequiredRerunNeeded
                dt((post, func, args, kwargs); invokelatest=true)
            else
                rethrow(e)
            end
        end
    else
        (post, func, args, kwargs) # act as the identity fuction
    end
end

function Base.getproperty(dta::DataAdviceAmalgamation, prop::Symbol)
    if getfield(dta, :plugins_wanted) != getfield(dta, :plugins_used)
        plugins_availible =
            filter(plugin -> plugin.name in getfield(dta, :plugins_wanted), PLUGINS)
        if getfield.(plugins_availible, :name) != getfield(dta, :plugins_used)
            advisors = getfield.(plugins_availible, :advisors) |>
                Iterators.flatten |> collect |> Vector{DataAdvice}
            sort!(advisors, by = t -> t.priority)
            setfield!(dta, :advisors, advisors)
            setfield!(dta, :adviseall, ∘(reverse(advisors)...))
            setfield!(dta, :plugins_used, getfield.(plugins_availible, :name))
        end
    end
    getfield(dta, prop)
end

DataAdviceAmalgamation(plugins::Vector{String}) =
    DataAdviceAmalgamation(identity, DataAdvice[], plugins, String[])

DataAdviceAmalgamation(collection::DataCollection) =
    DataAdviceAmalgamation(collection.plugins)

DataAdviceAmalgamation(dta::DataAdviceAmalgamation) = # for re-building
    DataAdviceAmalgamation(dta.plugins_wanted)

function (dta::DataAdviceAmalgamation)(
    annotated_func_call::Tuple{Function, Function, Tuple, _KWARGS_TYPE})
    dta.adviseall(annotated_func_call)
end

function (dta::DataAdviceAmalgamation)(func::Function, args...; kwargs...)
    # @info "Calling $func($(join(string.(args), ", ")))"
    post::Function, func2::Function, args2::Tuple, kwargs2::_KWARGS_TYPE =
        dta((identity, func, args, kwargs))
    # @info "Applying $(length(dta.advisers)) advisors to '$func($args, $kwargs)'"
    func2(args2...; kwargs2...) |> post
end
