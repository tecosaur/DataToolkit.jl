const REMOVE_DOC = md"""
Remove a data set

## Usage

    data> remove IDENTIFIER
"""

"""
    remove(input::AbstractString)

Parse and call the repl-format remove command `input`.
"""
function remove(input::AbstractString)
    if all(isspace, input)
        printstyled(" ! ", color=:yellow, bold=true)
        println("Specify a DataSet to remove")
        return
    end
    ident = try parse(Identifier, input) catch _
        printstyled(" ! ", color=:red, bold=true)
        println("Could not parse '$input' as an identifier")
        return
    end
    dataset = try resolve(ident) catch err
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
    confirm_yn(" Are you sure you want to remove $(dataset.name)?") || return nothing
    delete!(dataset)
    printstyled(" ✓ Done\n", color=:green)
end
