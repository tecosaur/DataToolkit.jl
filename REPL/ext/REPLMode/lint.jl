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
        DataToolkitCore.lintfix(report)
    end
    if isempty(STACK)
        printstyled(" ! ", color=:yellow, bold=true)
        println("The data collection stack is empty")
    elseif all(isspace, input)
        dolint(first(STACK))
    else
        try
            collection = getlayer(
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

# Implements `../../../Core/src/interaction/lint.jl`.
function DataToolkitCore.linttryfix(fixprompt::Vector{Tuple{Int, DataToolkitCore.LintItem}})
    printstyled(length(fixprompt), color=:light_white)
    print(ifelse(length(fixprompt) == 1, " issue (", " issues ("))
    for fixitem in fixprompt
        i, lintitem = fixitem
        printstyled(i, color=first(DataToolkitCore.LINT_SEVERITY_MESSAGES[lintitem.severity]))
        fixitem === last(fixprompt) || print(", ")
    end
    print(") can be manually fixed.\n")
    if confirm_yn("Would you like to try?", true)
        lastsource::Any = nothing
        objinfo(c::DataCollection) =
            printstyled("• ", c.name, '\n', color=:blue, bold=true)
        function objinfo(d::DataSet)
            printstyled("• ", d.name, color=:blue, bold=true)
            printstyled(" ", d.uuid, "\n", color=:light_black)
        end
        objinfo(a::A) where {A <: DataTransformer} =
            printstyled("• ", first(A.parameters), ' ',
                        join(lowercase.(split(string(nameof(A)), r"(?=[A-Z])")), ' '),
                        " for ", a.dataset.name, '\n', color=:blue, bold=true)
        objinfo(::DataLoader{driver}) where {driver} =
            printstyled("• ", driver, " loader\n", color=:blue, bold=true)
        objinfo(::DataWriter{driver}) where {driver} =
            printstyled("• ", driver, " writer\n", color=:blue, bold=true)
        for (i, lintitem) in fixprompt
            if lintitem.source !== lastsource
                objinfo(lintitem.source)
                lastsource = lintitem.source
            end
            printstyled("  [", i, "]: ", bold=true,
                        color=first(DataToolkitCore.LINT_SEVERITY_MESSAGES[lintitem.severity]))
            print(first(split(lintitem.message, '\n')), '\n')
            try
                lintitem.fixer(lintitem)
            catch e
                if e isa InterruptException
                    printstyled("!", color=:red, bold=true)
                    print(" Aborted\n")
                else
                    rethrow()
                end
            end
        end
        true
    else
        false
    end
end
