function repl_show(input::AbstractString)
    if isempty(input)
        printstyled(" ! ", color=:yellow, bold=true)
        println("Provide a dataset to be shown")
    else
        ds = resolve(input)
        show(ds)
        print('\n')
        if ds isa DataSet
            print("  UUID:    ")
            printstyled(ds.uuid, '\n', color=:light_magenta)
            if !isnothing(get(ds, "description"))
                indented_desclines =
                    join(split(strip(get(ds, "description")),
                                '\n'), "\n   ")
                println("\n  “\e[3m", indented_desclines, "\e[m”")
            end
        end
        nothing
    end
end

completions(::ReplCmd{:show}, sofar::AbstractString) =
    complete_dataset(sofar)
