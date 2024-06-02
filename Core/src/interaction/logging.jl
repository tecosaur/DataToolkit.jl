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
        Timer(delay) do _
            @info message _module=mod _file=file _line=line
        end
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
            finally
                isnothing(log_task) || close(log_task)
            end
            result
        end
    end
end
