const REMOVE_DOC = md"""
Remove a data set

## Usage

    data> remove IDENTIFIER
"""

"""
    remove(io::IO, input::AbstractString)

Parse and call the repl-format remove command `input`.
"""
function remove(io::IO, input::AbstractString)
    if all(isspace, input)
        printstyled(io, " ! ", color=:yellow, bold=true)
        println(io, "Specify a DataSet to remove")
        return
    end
    ident = try parse(Identifier, input) catch _
        printstyled(io, " ! ", color=:red, bold=true)
        println(io, "Could not parse '$input' as an identifier")
        return
    end
    foreach(refresh!, STACK)
    dataset = try
        resolve(ident)
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
    if !iswritable(dataset.collection)
        printstyled(io, " ! ", color=:red, bold=true)
        println(io, "The data collection $(dataset.name) belongs to is read-only")
        return
    end
    confirm_yn(io, " Are you sure you want to remove $(dataset.name)?") || return nothing
    delete!(dataset)
    printstyled(io, " ✓ Done\n", color=:green)
end
