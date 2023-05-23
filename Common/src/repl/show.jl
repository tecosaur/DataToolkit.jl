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
        show(dataset)
        print('\n')
        if dataset isa DataSet
            print("  UUID:    ")
            printstyled(dataset.uuid, '\n', color=:light_magenta)
            if !isnothing(get(dataset, "description"))
                indented_desclines =
                    join(split(strip(get(dataset, "description")),
                                '\n'), "\n   ")
                println("\n  “\e[3m", indented_desclines, "\e[m”")
            end
        end
        nothing
    end
end

completions(::ReplCmd{:show}, sofar::AbstractString) =
    complete_dataset(sofar)
