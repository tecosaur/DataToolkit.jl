Advice(@nospecialize(f::Function)) = Advice(DEFAULT_DATA_ADVISOR_PRIORITY, f)

Base.methods(dt::Advice) = methods(dt.f)

"""
    (advice::Advice)((post::Function, func::Function, args::Tuple, kwargs::NamedTuple))

Apply `advice` to the function call `func(args...; kwargs...)`, and return the
new `(post, func, args, kwargs)` tuple.
"""
function (dt::Advice)(callform::Tuple{Function, Function, Tuple, NamedTuple})
    @nospecialize
    post, func, args, kwargs = callform
    # Abstract-y `typeof`.
    atypeof(val::Any) = typeof(val)
    atypeof(val::Type) = Type{val}
    if hasmethod(dt.f, Tuple{typeof(func), atypeof.(args)...}, keys(kwargs))
        result = invokepkglatest(dt.f, func, args...; kwargs...)
        after, func, args, kwargs = if result isa Tuple{Function, Function, Tuple, NamedTuple}
            result # Fully specified form
        elseif result isa Tuple{Function, Function, Tuple}
            # Default kwargs
            result[1], result[2], result[3], NamedTuple()
        elseif result isa Tuple{Function, Tuple, NamedTuple}
            # Default post function
            identity, result[1], result[2], result[3]
        elseif result isa Tuple{Function, Tuple}
            # Default post function and kwargs
            identity, result[1], result[2], NamedTuple()
        else
            throw(ErrorException("Advice function produced invalid result: $(typeof(result))"))
        end
        if after !== identity
            post = post ∘ after
        end
        (post, func, args, kwargs)
    else
        (post, func, args, kwargs) # act as the identity fiction
    end
end

function (dt::Advice)(func::Function, args...; kwargs...)
    @nospecialize func args kwargs
    atypeof(val::Any) = typeof(val)
    atypeof(val::Type) = Type{val}
    if hasmethod(dt.f, Tuple{typeof(func), atypeof.(args)...}, keys(kwargs))
        post, func, args, kwargs = dt((identity, func, args, merge(NamedTuple(), kwargs)))
        result = func(args...; kwargs...)
        post(result)
    else
        func(args...; kwargs...)
    end
end


Base.empty(::Type{AdviceAmalgamation}) =
    AdviceAmalgamation(Advice[], String[], String[])

"""
    reinit(dta::AdviceAmalgamation)

Check that `dta` is well initialised before using it.

This does noting if `dta.plugins_wanted` is the same as `dta.plugins_used`.

When they differ, it re-builds the advisors function list based
on the currently available plugins, and updates `dta.plugins_used`.
"""
function reinit(dta::AdviceAmalgamation)
    if dta.plugins_wanted != dta.plugins_used
        plugins_available =
            filter(plugin -> plugin.name in dta.plugins_wanted, PLUGINS)
        if map(p -> p.name, plugins_available) != dta.plugins_used
            advisors = Advice[]
            for plg in plugins_available
                append!(advisors, plg.advisors)
            end
            sort!(advisors, by = t -> t.priority)
            dta.advisors = advisors
            dta.plugins_used = map(p -> p.name, plugins_available)
        end
    end
    dta
end

AdviceAmalgamation(plugins::Vector{String}) =
    AdviceAmalgamation(Advice[], plugins, String[])

AdviceAmalgamation(collection::DataCollection) =
    AdviceAmalgamation(collection.plugins)

AdviceAmalgamation(dta::AdviceAmalgamation) = # for re-building
    AdviceAmalgamation(dta.plugins_wanted)

function AdviceAmalgamation(advisors::Vector{<:Advice})
    advisors = sort(advisors, by = t -> t.priority)
    AdviceAmalgamation(advisors, String[], String[])
end

function (dta::AdviceAmalgamation)(annotated_func_call::Tuple{Function, Function, Tuple, NamedTuple})
    @nospecialize
    reinit(dta)
    for adv in dta.advisors
        annotated_func_call = adv(annotated_func_call)
    end
    annotated_func_call
end

function (dta::AdviceAmalgamation)(func::Function, args...; kwargs...)
    @nospecialize
    reinit(dta)
    post::Function, func2::Function, args2::Tuple, kwargs2::NamedTuple =
        dta((identity, func, args, merge(NamedTuple(), kwargs)))
    invokepkglatest(func2, args2...; kwargs2...) |> post
end

# Utility functions/macros

"""
    _dataadvise(thing::AdviceAmalgamation)
    _dataadvise(thing::Vector{Advice})
    _dataadvise(thing::Advice)
    _dataadvise(thing::DataCollection)
    _dataadvise(thing::DataSet)
    _dataadvise(thing::AbstractDataTransformer)

Obtain the relevant `AdviceAmalgamation` for `thing`.
"""
_dataadvise(amalg::AdviceAmalgamation) = amalg
_dataadvise(advs::Vector{<:Advice}) = AdviceAmalgamation(advs)
_dataadvise(adv::Advice) = AdviceAmalgamation([adv])
_dataadvise(col::DataCollection) = col.advise
_dataadvise(ds::DataSet) = _dataadvise(ds.collection)
_dataadvise(adt::AbstractDataTransformer) = _dataadvise(adt.dataset)

"""
    _dataadvisecall(func::Function, args...; kwargs...)

Identify the first data-like argument of `args` (i.e. a `DataCollection`,
`DataSet`, or `AbstractDataTransformer`), obtain its advise, and perform
an advised call of `func(args...; kwargs...)`.
"""
@generated function _dataadvisecall(func::Function, args...; kwargs...)
    dataarg = findfirst(
        a -> a <: DataCollection || a <: DataSet || a <: AbstractDataTransformer,
        args)
    if isnothing(dataarg)
        @warn """Attempted to generate advised function call for $(func.instance),
                 however none of the provided arguments were advisable.
                 Arguments types: $args
                 This function call will not be advised."""
        :(func(args...; kwargs...))
    else
        :(_dataadvise(args[$dataarg])(func, args...; kwargs...))
    end
end

"""
    @advise [source] f(args...; kwargs...)

Convert a function call `f(args...; kwargs...)` to an *advised* function call,
where the advise collection is obtained from `source` or the first data-like\\*
value of `args`.

\\* i.e. a `DataCollection`, `DataSet`, or `AbstractDataTransformer`

For example, `@advise myfunc(other, somedataset, rest...)` is equivalent to
`somedataset.collection.advise(myfunc, other, somedataset, rest...)`.

This macro performs a fairly minor code transformation, but should improve
clarity.
"""
macro advise(source::Union{Symbol, Expr}, funcall::Union{Expr, Nothing}=nothing)
    # Handle @advice(funcall), and ensure `source` is correct both ways.
    if isnothing(funcall)
        funcall = source
        source = GlobalRef(@__MODULE__, :_dataadvisecall)
    else
        source = Expr(:call,
                      GlobalRef(@__MODULE__, :_dataadvise),
                      source)
    end
    if funcall isa Symbol || funcall.head != :call
        # Symbol if `source` was a symbol, and `funcall` nothing.
        throw(ArgumentError("Cannot advise non-function call $funcall"))
    elseif length(funcall.args) < 2
        throw(ArgumentError("Cannot advise function call without arguments $funcall"))
    else
        args = if funcall.args[2] isa Expr && funcall.args[2].head == :parameters
            vcat(funcall.args[2], funcall.args[1], funcall.args[3:end])
        else funcall.args end
        Expr(:escape,
             Expr(:call,
                  source,
                  args...))
    end
end
