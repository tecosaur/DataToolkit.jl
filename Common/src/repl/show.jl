const SHOW_DOC = md"""
Show the dataset refered to by an identifier

## Usage

    data> show IDENTIFIER
"""

function repl_show(input::AbstractString)
    if isempty(input)
        printstyled(" ! ", color=:yellow, bold=true)
        println("Provide a dataset to be shown")
    else
        dataset = try resolve(input) catch _
            printstyled(" ! ", color=:red, bold=true)
            println("Could not resolve identifier: $input")
            return nothing
        end
        display(dataset)
        if dataset isa DataSet
            print("  UUID:    ")
            printstyled(dataset.uuid, '\n', color=:light_magenta)
            @advise show_extra(stdout, dataset)
        end
        nothing
    end
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

completions(::ReplCmd{:show}, sofar::AbstractString) =
    complete_dataset(sofar)
