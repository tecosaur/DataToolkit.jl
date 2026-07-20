const CHECK_DOC = md"""
Check the state for potential issues

By default, this operates on the active collection, however it can
also be applied to any other collection or a specific data set.

## Usage

    data> check (runs on the active collection)
    data> check COLLECTION
    data> check IDENTIFIER
"""

function repl_lint(io::IO, input::AbstractString)
    function dolint(thing)
        report = LintReport(thing)
        show(io, MIME("text/plain"), report)
        print(io, "\n\n")
        DataToolkitCore.lintfix(io, report)
    end
    if isempty(STACK)
        printstyled(io, " ! ", color=:yellow, bold=true)
        println(io, "The data collection stack is empty")
    elseif all(isspace, input)
        refresh!(first(STACK))
        dolint(first(STACK))
    else
        index = tryparse(Int, input)
        collection = if !isnothing(index)
            if index in axes(STACK, 1) STACK[index] end
        else
            try getlayer(@something(tryparse(UUID, input), String(input))) catch _ end
        end
        if !isnothing(collection)
            refresh!(collection)
            dolint(collection)
        else
            dset = try resolve(input) catch err
                err isa IdentifierException || rethrow()
                printstyled(io, " ! ", color=:red, bold=true)
                return println(io, "Could not resolve identifier: $input")
            end
            mtime0 = if !isnothing(dset.collection.source) dset.collection.source.mtime end
            refresh!(dset.collection)
            mtime1 = if !isnothing(dset.collection.source) dset.collection.source.mtime end
            if mtime0 != mtime1
                dset = resolve(input)
            end
            dolint(dset)
        end
    end
end

# Implements `../../../Core/src/interaction/lint.jl`.
function DataToolkitCore.linttryfix(io::IO, fixprompt::Vector{Tuple{Int, DataToolkitCore.LintItem}})
    printstyled(io, length(fixprompt), color=:light_white)
    print(io, ifelse(length(fixprompt) == 1, " issue (", " issues ("))
    for fixitem in fixprompt
        i, lintitem = fixitem
        printstyled(io, i, color=first(DataToolkitCore.LINT_SEVERITY_MESSAGES[lintitem.severity]))
        fixitem === last(fixprompt) || print(io, ", ")
    end
    print(io, ") can be manually fixed.\n")
    if confirm_yn(io, "Would you like to try?", true)
        lastsource::Any = nothing
        objinfo(c::DataCollection) =
            printstyled(io, "• ", c.name, '\n', color=:blue, bold=true)
        function objinfo(d::DataSet)
            printstyled(io, "• ", d.name, color=:blue, bold=true)
            printstyled(io, " ", d.uuid, "\n", color=:light_black)
        end
        objinfo(a::A) where {A <: DataTransformer} =
            printstyled(io, "• ", driverof(A), ' ',
                        join(lowercase.(split(string(nameof(A)), r"(?=[A-Z])")), ' '),
                        " for ", a.dataset.name, '\n', color=:blue, bold=true)
        objinfo(::DataLoader{driver}) where {driver} =
            printstyled(io, "• ", driver, " loader\n", color=:blue, bold=true)
        objinfo(::DataWriter{driver}) where {driver} =
            printstyled(io, "• ", driver, " writer\n", color=:blue, bold=true)
        for (i, lintitem) in fixprompt
            if lintitem.source !== lastsource
                objinfo(lintitem.source)
                lastsource = lintitem.source
            end
            printstyled(io, "  [", i, "]: ", bold=true,
                        color=first(DataToolkitCore.LINT_SEVERITY_MESSAGES[lintitem.severity]))
            print(io, first(split(lintitem.message, '\n')), '\n')
            try
                lintitem.fixer(io, lintitem)
            catch e
                if e isa InterruptException
                    printstyled(io, "!", color=:red, bold=true)
                    print(io, " Aborted\n")
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
