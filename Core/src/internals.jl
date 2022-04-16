function Base.convert(::Type{Type}, qt::QualifiedType)
    getfield(getfield(Main, qt.parentmodule), qt.name)
end

Base.methods(dt::DataTransducer) = methods(dt.f)
function (dt::DataTransducer{C, F})(
    (context, func, args, kwargs)::Tuple{Any, Function, Tuple, pairs(NamedTuple)}) where {C, F}
    if context isa C && func isa F && applicable(dt.f, context, func, args, kwargs) #&& applicable(func, args...; kwargs...)
        dt.f(context, func, args, kwargs)
    else
        (context, func, args, kwargs) # act as the identiy fuction
    end
end

function Base.getproperty(dta::DataTransducerAmalgamation, prop::Symbol)
    if getfield(dta, :plugins_wanted) != getfield(dta, :plugins_used)
        plugins_availible =
            filter(plugin -> plugin.name in getfield(dta, :plugins_wanted), PLUGINS)
        if getfield.(plugins_availible, :name) != getfield(dta, :plugins_used)
            transducers = getfield.(plugins_availible, :transducers) |>
                Iterators.flatten |> collect
            sort!(transducers, by = t -> t.priority)
            setfield!(dta, :transducers, transducers)
            setfield!(dta, :transduceall, ∘(reverse(transducers)...))
            setfield!(dta, :plugins_used, getfield.(plugins_availible, :name))
        end
    end
    getfield(dta, prop)
end

function (dta::DataTransducerAmalgamation)(
    context_func_args_kwargs::Tuple{Any, Function, Tuple, pairs(NamedTuple)})
    dta.transduceall(context_func_args_kwargs)
end

function (dta::DataTransducerAmalgamation)(func::Function, context::Any, args...; kwargs...)
    context2, func2::Function, args2::Tuple, kwargs2::pairs(NamedTuple) =
        dta((context, func, args, kwargs))
    func2(context2, args2...; kwargs2...)
end
