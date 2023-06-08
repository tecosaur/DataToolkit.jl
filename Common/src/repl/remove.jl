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
    ident = try parse(Identifier, input) catch _
        printstyled(" ! ", color=:red, bold=true)
        println("Could not parse '$input' as an identifier")
    end
    dataset = try resolve(ident) catch _
        printstyled(" ! ", color=:red, bold=true)
        println("Could not resolve identifier: $input")
        return nothing
    end
    confirm_yn(" Are you sure you want to remove $(dataset.name)?") || return nothing
    remove!(dataset)
    printstyled(" ✓ Done\n", color=:green)
end

completions(::ReplCmd{:remove}, sofar::AbstractString) =
    complete_dataset(sofar)
