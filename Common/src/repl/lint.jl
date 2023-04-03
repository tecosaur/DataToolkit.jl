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
    elseif isempty(input)
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

completions(::ReplCmd{:check}, sofar::AbstractString) =
    sort(vcat(complete_collection(sofar),
              complete_dataset(sofar)),
         by=natkeygen)
