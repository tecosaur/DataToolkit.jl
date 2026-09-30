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

The failure of the task [`@log_do`](@ref) ran its expression in.

It displays as the expression's exceptions would have, had it run in the
caller: the one that ended the task, then any it was raised while handling.
Use [`unwrap_logtask`](@ref) to inspect what was thrown.
"""
struct LogTaskError <: Exception
    task::Task
end

"""
    unwrap_logtask(err) -> Any

The exception `err` stands for, without [`LogTaskError`](@ref) wrapping: the
exception that ended the task (itself unwrapped, as `@log_do`s nest), or `err`.

A `catch` that tests what a data operation threw should test
`unwrap_logtask(err)`, and `rethrow()` what it can't handle, so the task's
backtrace is kept.
"""
unwrap_logtask(err) = err
unwrap_logtask(err::LogTaskError) = unwrap_logtask(err.task.exception)

function Base.showerror(io::IO, err::LogTaskError, bt; backtrace=true)
    stack = Base.current_exceptions(err.task)
    # A deserialised task keeps its exception, but not its exception stack.
    isempty(stack) && return showerror(io, err.task.exception, bt; backtrace)
    callerframes = if backtrace stackframes(bt) end
    Base.show_exception_stack(io, map(stack) do (exception, taskbt)
        frames = if backtrace
            merged = vcat(stacktrace(taskbt), callerframes)
            SIMPLIFY_STACKTRACES[] &&
                filter!(sf -> sf.file != Symbol(@__FILE__), merged)
            strip_stacktrace_advice!(merged)
        end
        (exception, frames)
    end)
end

Base.showerror(io::IO, err::LogTaskError) = showerror(io, err, nothing; backtrace=false)

"""
    @log_do category message [expr]

Return the result of `expr`, logging `message` with `category` if
appropriate to do so.
"""
macro log_do(category::String, message, expr::Union{Expr, Nothing} = nothing)
    quote
        let log_task = wait_maybe_log(
                $category, $(esc(message));
                mod=@__MODULE__, file=$(String(something(__source__.file, ""))), line=$(__source__.line))
            result = try
                fetch(@spawn $(esc(expr)))
            catch err
                # Only the task's failure is ours to wrap; an interrupt is the caller's.
                err isa TaskFailedException || rethrow()
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
