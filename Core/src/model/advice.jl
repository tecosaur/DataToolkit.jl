DataAdvice(f::Function) =
    DataAdvice(DEFAULT_DATA_ADVISOR_PRIORITY, f)

Base.methods(dt::DataAdvice) = methods(dt.f)

"""
    (advice::DataAdvice)((post::Function, func::Function, args::Tuple, kwargs::NamedTuple))

Apply `advice` to the function call `func(args...; kwargs...)`, and return the
new `(post, func, args, kwargs)` tuple.
"""
function (dt::DataAdvice{F, C})(
    (post, func, args, kwargs)::Tuple{Function, Function, Tuple, NamedTuple}) where {F, C}
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
        (post, func, args, kwargs) # act as the identity fuction
    end
end

function (dt::DataAdvice)(func::Function, args...; kwargs...)
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

Base.empty(::Type{DataAdviceAmalgamation}) =
    DataAdviceAmalgamation(identity, DataAdvice[], String[], String[])

# When getting a property of a `DataAdviceAmalgamation`, first check
# if the `:plugins_wanted` field is satisfied. Should it not be,
# regenerate the `:advisors`, `:adviseall`, and `:plugins_used` fields
# based on the currently availible plugins and `:plugins_wanted`.
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

function DataAdviceAmalgamation(advisors::Vector{<:DataAdvice})
    advisors = sort(advisors, by = t -> t.priority)
    DataAdviceAmalgamation(∘(reverse(advisors)...), advisors, String[], String[])
end

function (dta::DataAdviceAmalgamation)(
    annotated_func_call::Tuple{Function, Function, Tuple, NamedTuple})
    dta.adviseall(annotated_func_call)
end

function (dta::DataAdviceAmalgamation)(func::Function, args...; kwargs...)
    post::Function, func2::Function, args2::Tuple, kwargs2::NamedTuple =
        dta((identity, func, args, merge(NamedTuple(), kwargs)))
    invokepkglatest(func2, args2...; kwargs2...) |> post
end

# Utility functions/macros

"""
    _dataadvise(thing::DataAdviceAmalgamation)
    _dataadvise(thing::Vector{DataAdvice})
    _dataadvise(thing::DataAdvice)
    _dataadvise(thing::DataCollection)
    _dataadvise(thing::DataSet)
    _dataadvise(thing::AbstractDataTransformer)

Obtain the relevant `DataAdviceAmalgamation` for `thing`.
"""
_dataadvise(amalg::DataAdviceAmalgamation) = amalg
_dataadvise(advs::Vector{<:DataAdvice}) = DataAdviceAmalgamation(advs)
_dataadvise(adv::DataAdvice) = DataAdviceAmalgamation([adv])
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
                 This funtion call call will not be advised."""
        :(func(args...; kwargs...))
    else
        :(_dataadvise(args[$dataarg])(func, args...; kwargs...))
    end
end

"""
    @advice [source] f(args...; kwargs...)

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
    # Handle @advice(funcall), and ensure `source` is corruct both ways.
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
