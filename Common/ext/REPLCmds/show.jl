const SHOW_DOC = md"""
Show the dataset refered to by an identifier

## Usage

    data> show IDENTIFIER
"""

function repl_show(input::AbstractString)
    if all(isspace, input)
        printstyled(" ! ", color=:yellow, bold=true)
        println("Specify a DataSet shown")
        return
    end
    dataset = try resolve(input) catch err
        printstyled(" ! ", color=:red, bold=true)
        println("Could not resolve identifier: $input")
        if err isa IdentifierException
            print(' ')
            showerror(stdout, err)
            print('\n')
            return
        else
            rethrow()
        end
    end
    display(dataset)
    if dataset isa DataSet
        print("  UUID:    ")
        printstyled(dataset.uuid, '\n', color=:light_magenta)
        @advise show_extra(stdout, dataset)
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
        print("\n\e[2;3m")
        show(stdout, MIME("text/plain"), desc)
        print("\e[m\n")
    end
end
