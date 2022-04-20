DataAdvice(f::Function) =
    DataAdvice(DEFAULT_DATA_ADVISOR_PRIORITY, f)

Base.methods(dt::DataAdvice) = methods(dt.f)

function (dt::DataAdvice{C, F})(
    (post, func, args, kwargs)::Tuple{Function, Function, Tuple, pairs(NamedTuple)}) where {C, F}
    # @info "Testing $dt"
    if hasmethod(dt.f, Tuple{typeof(post), typeof(func), typeof.(args)...}, keys(kwargs))
        # @info "Applying $dt"
        result = dt.f(post, func, args...; kwargs...)
        if result isa Tuple{Function, Function, Tuple}
            k0 = Base.Pairs{Symbol, Union{}, Tuple{}, NamedTuple{(), Tuple{}}}(NamedTuple(),())
            post, func, args = result
            (post, func, args, k0)
        else
            result
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
                Iterators.flatten |> collect
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
    annotated_func_call::Tuple{Function, Function, Tuple, pairs(NamedTuple)})
    dta.adviseall(annotated_func_call)
end

function (dta::DataAdviceAmalgamation)(func::Function, args...; kwargs...)
    # @info "Calling $func($(join(string.(args), ", ")))"
    post::Function, func2::Function, args2::Tuple, kwargs2::pairs(NamedTuple) =
        dta((identity, func, args, kwargs))
    # @info "Applying $(length(dta.advisers)) advisors to '$func($args, $kwargs)'"
    func2(args2...; kwargs2...) |> post
end
