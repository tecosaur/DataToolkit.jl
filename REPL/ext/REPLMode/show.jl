const SHOW_DOC = md"""
Show the dataset refered to by an identifier

## Usage

    data> show IDENTIFIER
"""

function repl_show(io::IO, input::AbstractString)
    if all(isspace, input)
        printstyled(io, " ! ", color=:yellow, bold=true)
        println(io, "Specify a DataSet shown")
        return
    end
    foreach(refresh!, STACK)
    dataset = try
        resolve(input)
    catch err
        printstyled(io, " ! ", color=:red, bold=true)
        println(io, "Could not resolve identifier: $input")
        if err isa IdentifierException
            print(io, ' ')
            showerror(io, err, backtrace(), backtrace = false)
            print(io, '\n')
            return
        else
            rethrow()
        end
    end
    show(io, MIME("text/plain"), dataset)
    if dataset isa DataSet
        print(io, "  UUID:    ")
        printstyled(io, dataset.uuid, '\n', color=:light_magenta)
        if !isempty(dataset.parameters) && !(length(dataset.parameters) == 1 && first(keys(dataset.parameters)) == "description")
            println(io, "  Parameters:")
            pkeys = collect(keys(dataset.parameters))
            pkeypad = maximum(textwidth, pkeys)
            for key in sort(pkeys, by=natkeygen)
                key == "description" && continue
                print(io, "    ", lpad(key, pkeypad), ' ')
                printstyled(io, dataset.parameters[key], '\n', color=:light_cyan)
            end
        end
        @advise show_extra(io, dataset)
    end
    nothing
end

"""
    show_extra(io::IO, dataset::DataSet)

Print extra information (namely this description) about `dataset` to `io`.

!!! info "Advice point"
    This function call is advised within the `repl_show` invocation.
"""
function show_extra(io::IO, dataset::DataSet)
    if haskey(dataset.parameters, "description")
        desc = get(dataset, "description") |> Markdown.parse
        print(io, "\n\e[2;3m")
        show(io, MIME("text/plain"), desc)
        print(io, "\e[m\n")
    end
end
