const CHECK_DOC = md"""
Check the state for potential issues

By default, this operates on the active collection, however it can
also be applied to any other collection or a specific data set.

## Usage

    data> check (runs on the active collection)
    data> check COLLECTION
    data> check IDENTIFIER
"""

function repl_lint(input::AbstractString)
    function dolint(thing)
        report = LintReport(thing)
        show(report)
        print("\n\n")
        DataToolkitBase.lintfix(report)
    end
    if isempty(STACK)
        printstyled(" ! ", color=:yellow, bold=true)
        println("The data collection stack is empty")
    elseif all(isspace, input)
        dolint(first(STACK))
    else
        try
            collection = DataToolkitBase.getlayer(
                @something(tryparse(Int, input),
                           tryparse(UUID, input),
                           String(input)))
            dolint(collection)
        catch
            dataset = resolve(input, resolvetype=false)
            dolint(dataset)
        end
    end
end
