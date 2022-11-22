const DELETE_DOC = "Delete a data set

Examples:
  delete mydata"

"""
    delete(input::AbstractString)
Parse and call the repl-format delete command `input`.
"""
function delete(input::AbstractString)
    ident = try parse(Identifier, input) catch _
        printstyled(" ! ", color=:red, bold=true)
        println("Could not parse '$input' as an identifier")
    end
    dataset = try resolve(ident) catch _
        printstyled(" ! ", color=:red, bold=true)
        println("Could not resolve identifier: $input")
        return nothing
    end
    confirm_yn(" Are you sure you want to delete $(dataset.name)?") || return nothing
    delete!(dataset)
    printstyled(" ✓ Done\n", color=:green)
end

completions(::ReplCmd{:delete}, sofar::AbstractString) =
    complete_dataset(sofar)
