"""
    should_log(category::String) -> Bool

Determine whether a message should be logged based on its `category`.

The category string can contain any number of subcategories separated by
colons. If any parent category is enabled, the subcategory is also enabled.
"""
function should_log(category::String)
    condition = @load_preference("log", true)
    condition isa Bool && return condition
    category in condition && return true
    while ':' in category
        category = chopsuffix(category, r":[^:]+$")
        category in condition && return true
    end
    false
end

"""
    wait_maybe_log(category::String, message::AbstractString; mod::Module, file::String, line::Int) -> Timer

Wait for a delay before logging `message` with `category` if `should_log(category)`.

The log is produced with metadata from `mod`, `file`, and `line`.
"""
function wait_maybe_log(category::String, message::AbstractString; mod::Module, file::String, line::Int)
    should_log(category) || return Timer(0)
    delay = @load_preference("logdelay", DEFAULT_LOG_DELAY)
    if delay <= 0
        @info message _module=mod _file=file _line=line
        Timer(0)
    else
        initialworld = Base.get_world_counter()
        Timer(delay; interval = delay) do tmr
            if Base.get_world_counter() > initialworld
                # We don't want to show a log just because of compilation time.
                initialworld = Base.get_world_counter()
            else
                @info message _module=mod _file=file _line=line
                close(tmr)
            end
        end
    end
end

"""
    LogTaskError <: Exception

A thin wrapper around a `TaskFailedException` that only
prints the stack trace of the exception within the task.
"""
struct LogTaskError <: Exception
    task::Task
end

function Base.showerror(io::IO, ex::LogTaskError, bt; backtrace=true)
    stack = Base.current_exceptions(ex.task)
    if length(stack) >= 1 # Should only be a depth-1 stack
        exc1, bt1 = stack[1]
        bt_merged = vcat(stacktrace(bt1), bt)
        # If a `LogTaskError` has been thrown, then there's
        # no issue with the logging itself, and so we may
        # as well remove the `@log_do` involvement from the
        # backtrace.
        SIMPLIFY_STACKTRACES[] &&
            filter!(sf -> sf.file != Symbol(@__FILE__), bt_merged)
        showerror(io, exc1, bt_merged; backtrace)
    elseif backtrace
        Base.show_backtrace(io, bt)
    end
end

"""
    @log_do category message [expr]

Return the result of `expr`, logging `message` with `category` if
appropriate to do so.
"""
macro log_do(category::String, message, expr::Union{Expr, Nothing} = nothing)
    quote
        let log_task = wait_maybe_log(
                $category, $(esc(message));
                mod=@__MODULE__, file=$(String(__source__.file)), line=$(__source__.line))
            result = try
                fetch(@spawn $(esc(expr)))
            catch err
                LogTaskError(err.task)
            finally
                isnothing(log_task) || close(log_task)
            end
            # We do this outside of the `catch` to avoid
            # creating an exception stack including
            # the original `TaskFailedException`.
            result isa LogTaskError && throw(result)
            result
        end
    end
end
