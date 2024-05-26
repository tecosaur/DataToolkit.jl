"""
    stack_list(::AbstractString; maxwidth::Int=displaysize(stdout)[2])
Print a table listing all of the current data collections on the stack.
"""
function stack_list(::AbstractString; maxwidth::Int=displaysize(stdout)[2])
    table_rows = displaytable(
        ["#", "Name", "Datasets", "Writable", "Plugins"],
        map(enumerate(STACK)) do (i, collection)
            [string(i), something(collection.name, ""),
             length(collection.datasets),
             ifelse(iswritable(collection), "yes", "no"),
             join(collection.plugins, ", ")]
        end; maxwidth)
    for row in table_rows
        print(stderr, ' ', row, '\n')
    end
end

"""
    stack_promote(input::AbstractString)
Parse and call the repl-format stack promotion command `input`.

`input` should consist of a data collection identifier and optionally a
promotion amount, either an integer or the character '*'.
"""
function stack_promote(input::AbstractString)
    ident, repeat = match(r"^(.*?)((?: +-?\d+| +\*)?)$", input).captures
    DataToolkitBase.stack_move(
        @something(tryparse(Int, ident),
                   tryparse(UUID, ident),
                   String(ident)),
        -if strip(repeat) == "*"
            length(STACK)
        else
            something(tryparse(Int, repeat), 1)
        end)
    nothing
end

"""
    stack_demote(input::AbstractString)
Parse and call the repl-format stack demote command `input`.

`input` should consist of a data collection identifier and optionally a
promotion amount, either an integer or the character '*'.
"""
function stack_demote(input::AbstractString)
    ident, repeat = match(r"^(.*?)((?: +-?\d+| +\*)?)$", input).captures
    DataToolkitBase.stack_move(
        @something(tryparse(Int, ident),
                   tryparse(UUID, ident),
                   String(ident)),
        if strip(repeat) == "*"
            length(STACK)
        else
            something(tryparse(Int, repeat), 1)
        end)
    nothing
end

"""
    stack_load(input::AbstractString)
Parse and call the repl-format stack loader command `input`.

`input` should consist of a path to a Data TOML file or a folder containing a
Data.toml file. The path may be preceeded by a position in the stack to be
loaded to, either an integer or the character '*'.

`input` may also be the name of an existing data collection, in which case its
path is substituted.
"""
function stack_load(input::AbstractString)
    position, path = match(r"^((?:\d+ +)?)(.*)$", input).captures
    file = if !isempty(path)
        if !endswith(path, ".toml") && !isdir(path) &&
            !isnothing(findfirst(c -> c.name == path, STACK))
            DataToolkitBase.getlayer(path).path
        else
            abspath(expanduser(path))
        end
    elseif !isnothing(Base.active_project(false)) &&
        isfile(joinpath(Base.active_project(false), "Data.toml"))
        dirname(Base.active_project(false))
    elseif isfile("Data.toml")
        "Data.toml"
    else
        printstyled(" ! ", color=:yellow, bold=true)
        println("Provide a path to the Data TOML file to load")
        return nothing
    end
    if isdir(file)
        file = joinpath(file, "Data.toml")
    end
    if !isfile(file)
        printstyled(" ! ", color=:red, bold=true)
        println("File '$input' does not exist")
    else
        uuid = UUID(get(open(TOML.parse, file), "uuid", UUID(zero(UInt128))))
        existing = findfirst(c -> c.uuid == uuid, STACK)
        mod = if isnothing(existing) Main else STACK[existing].mod end
        loadcollection!(file, mod, index=something(tryparse(Int, position), 1))
    end
end

"""
    stack_remove(input::AbstractString)
Parse and call the repl-format stack removal command `input`.

`input` should consist of a data collection identifier.
"""
function stack_remove(input::AbstractString)
    if isempty(input)
        printstyled(" ! ", color=:yellow, bold=true)
        println("Identify the data collection that should be removed")
    else
        DataToolkitBase.stack_remove!(
            @something(tryparse(Int, input),
                       tryparse(UUID, input),
                       String(input)))
        nothing
    end
end

# TODO `stack edit`, with some sort of nice interactively re-orderable list

const STACK_SUBCOMMANDS = ReplCmd[
    ReplCmd{:stack_list}(
        "", "List the data collections of the data stack", stack_list),
    ReplCmd{:stack_promote}(
        "promote",
        md"""Move an entry up the stack

          An entry can be identified using any of the following:
          - The current position in the stack
          - The name of the data collection
          - The UUID of the data collection

          The number of positions the entry should be promoted by defaults to 1,
          but can optionally be specified by putting either an integer or the
          character `*` after the identifier. When `*` is given, the entry will
          be promoted to the top of the data stack.

          ## Examples with different identifier forms

              data> promote 2
              data> promote mydata
              data> promote 853a9f6a-cd5e-4447-a0a4-b4b2793e0a48

          ## Examples with different promotion degrees

              data> promote mydata
              data> promote mydata 3
              data> promote mydata *""",
        stack_promote),
    ReplCmd{:stack_demote}(
        "demote",
        md"""Move an entry down the stack

          An entry can be identified using any of the following:
          - The current position in the stack
          - The name of the data collection
          - The UUID of the data collection

          The number of positions the entry should be demoted by defaults to 1,
          but can optionally be specified by putting either an integer or the
          character `*` after the identifier. When `*` is given, the entry will
          be demoted to the bottom of the data stack.

          ## Examples with different identifier forms

              data> demote 2
              data> demote mydata
              data> demote 853a9f6a-cd5e-4447-a0a4-b4b2793e0a48

          ## Examples with different demotion degrees

              data> demote mydata
              data> demote mydata 3
              data> demote mydata *""",
        stack_demote),
    ReplCmd{:stack_load}(
        "load",
        md"""Load a data collection onto the top of the stack

          The data collection should be given by a path to either:
          - A Data TOML file
          - A folder containing a 'Data.toml' file

          The path can be optionally preceeded by an position to insert the
          loaded collection into the stack at. The default behaviour is to put
          the new collection at the top of the stack.

          ## Examples
              data> load path/to/mydata.toml
              data> load 2 somefolder/""",
        stack_load),
    ReplCmd{:stack_remove}(
        "remove",
        md"""Remove an entry from the stack

          An entry can be identified using any of the following:
          - The current position in the stack
          - The name of the data collection
          - The UUID of the data collection

          ## Examples

              data> remove 2
              data> remove mydata
              data> remove 853a9f6a-cd5e-4447-a0a4-b4b2793e0a48""",
        stack_remove),
]

function completions(::ReplCmd{:stack_load}, sofar::AbstractString)
    pathsofar = first(match(r"^(?:\d+ *)?(.*)$", sofar).captures)
    currentsegment = reverse(first(split(reverse(pathsofar), '/', limit=2, keepempty=true)))
    nextsegments = getfield.(first(REPL.REPLCompletions.complete_path(pathsofar, 0)), :path)
    if all(isspace, sofar) || '/' ∉ sofar
        append!(nextsegments, complete_collection(sofar))
        return Vector{String}(nextsegments)
    elseif isempty(nextsegments)
        return complete_collection(sofar)
    end
    (if !isempty(nextsegments)
         nextsegments
     else String[] end,
     String(currentsegment),
     !isempty(nextsegments))
end

completions(::ReplCmd{:stack_promote}, sofar::AbstractString) =
    complete_collection(sofar)

completions(::ReplCmd{:stack_demote}, sofar::AbstractString) =
    complete_collection(sofar)

completions(::ReplCmd{:stack_remove}, sofar::AbstractString) =
    complete_collection(sofar)
