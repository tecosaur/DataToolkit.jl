# Help command and related facilities

"""
    help(r::ReplCmd)

Print the help string for `r`.

When `r` has subcommands, the description will be followed by a table of its
subcommands.
"""
function help end

function help(r::ReplCmd{Function})
    if r.description isa AbstractString
        for line in eachsplit(rstrip(r.description), '\n')
            println("  ", line)
        end
    else
        display(r.description)
    end
end

function help(r::ReplCmd{Vector{ReplCmd}})
    if r.description isa AbstractString
        for line in eachsplit(rstrip(r.description), '\n')
            println("  ", line)
        end
    else
        display(r.description)
    end
    print('\n')
    help_cmd_table(commands = r.execute, sub=true)
end

"""
The help-string for the help command itself.
This contains the template string \"<SCOPE>\", which
is replaced with the relevant scope at runtime.
"""
const HELP_CMD_HELP =
    """Display help information on the available <SCOPE> commands

       For convenience, help information can also be accessed via '?', e.g. '?help'.

       Help for data transformers can also be accessed by asking for the help of the
       transformer name prefixed by ':' (i.e. ':transformer'), and a list of documented
       transformers can be pulled up with just ':'.

       Usage
       =====

       $REPL_PROMPT help
       $REPL_PROMPT help CMD
       $REPL_PROMPT help PARENT CMD
       $REPL_PROMPT PARENT help CMD
       $REPL_PROMPT help :
       $REPL_PROMPT help :TRANSFORMER
       """

"""
    displaytable(rows::Vector{<:Vector};
                 spacing::Integer=2, maxwidth::Int=80)

Return a `vector` of strings, formed from each row in `rows`.

Each string is of the same `displaywidth`, and individual values
are separated by `spacing` spaces. Values are truncated if necessary
to ensure the no row is no wider than `maxwidth`.
"""
function displaytable(rows::Vector{<:Vector};
                      spacing::Integer=2, maxwidth::Int=80)
    column_widths = min.(maxwidth,
                         maximum.(textwidth.(string.(getindex.(rows, i)))
                                  for i in 1:length(rows[1])))
    if sum(column_widths) > maxwidth
        # Resize columns according to the square root of their width
        rootwidths = sqrt.(column_widths)
        table_width = sum(column_widths) + spacing * length(column_widths)
        rootcorrection = sum(column_widths) / sum(sqrt, column_widths)
        rootwidths = rootcorrection .* sqrt.(column_widths) .* maxwidth/table_width
        # Look for any expanded columns, and redistribute their excess space
        # proportionally.
        overwides = column_widths .< rootwidths
        if any(overwides)
            gap = sum((rootwidths .- column_widths)[overwides])
            rootwidths[overwides] = column_widths[overwides]
            @. rootwidths[.!overwides] += gap * rootwidths[.!overwides]/sum(rootwidths[.!overwides])
        end
        column_widths = max.(1, floor.(Int, rootwidths))
    end
    makelen(content::String, len::Int) =
        if length(content) <= len
            rpad(content, len)
        else
            string(content[1:len-1], '…')
        end
    makelen(content::Any, len::Int) = makelen(string(content), len)
    map(rows) do row
        join([makelen(col, width) for (col, width) in zip(row, column_widths)],
             ' '^spacing)
    end
end

"""
    displaytable(headers::Vector, rows::Vector{<:Vector};
                 spacing::Integer=2, maxwidth::Int=80)

Prepend the `displaytable` for `rows` with a header row given by `headers`.
"""
function displaytable(headers::Vector, rows::Vector{<:Vector};
                      spacing::Integer=2, maxwidth::Int=80)
    rows = displaytable(vcat([headers], rows); spacing, maxwidth)
    rule = '─'^length(rows[1])
    vcat("\e[1m" * rows[1] * "\e[0m", rule, rows[2:end])
end

"""
    help_cmd_table(; maxwidth::Int=displaysize(stdout)[2],
                   commands::Vector{ReplCmd}=REPL_CMDS,
                   sub::Bool=false)

Print a table showing the triggers and descriptions (limited to the first line)
of `commands`, under the headers "Command" and "Action" (or "Subcommand" if
`sub` is set). The table is truncated if necessary so it is no wider than
`maxwidth`.
"""
function help_cmd_table(; maxwidth::Int=displaysize(stdout)[2]-2,
                        commands::Vector{ReplCmd}=REPL_CMDS,
                        sub::Bool=false)
    help_headings = [if sub "Subcommand" else "Command" end, "Action"]
    help_lines = map(commands) do replcmd
        String[replcmd.name,
               first(split(string(replcmd.description), '\n'))]
    end
    push!(help_lines, ["help", "Display help text for commands and transformers"])
    map(displaytable(help_headings, help_lines; maxwidth)) do row
        print(stderr, "  ", row, '\n')
    end
end

"""
    help_show(cmd::AbstractString; commands::Vector{ReplCmd}=REPL_CMDS)

If `cmd` refers to a command in `commands`, show its help (via `help`).
If `cmd` is empty, list `commands` via `help_cmd_table`.
"""
function help_show(cmd::AbstractString; commands::Vector{ReplCmd}=REPL_CMDS)
    if all(isspace, cmd)
        help_cmd_table(; commands)
        println("\n  \e[2;3mCommands can also be triggered by unique prefixes or substrings.\e[22;23m")
    else
        repl_cmd = find_repl_cmd(strip(cmd); commands, warn=true)
        if !isnothing(repl_cmd)
            help(repl_cmd)
        end
    end
    nothing
end

"""
    transformer_docs(name::Symbol, type::Symbol=:any)

Return the documentation for the transformer identified by `name`,
or `nothing` if no documentation entry could be found.
"""
function transformer_docs(name::Symbol, type::Symbol=:any)
    tindex = findfirst(
        t -> first(t)[2] === name && (type === :any || first(t)[1] === type),
        TRANSFORMER_DOCUMENTATION)
    if !isnothing(tindex)
        last(TRANSFORMER_DOCUMENTATION[tindex])
    end
end

"""
    transformers_printall()

Print a list of all documented data transformers, by category.
"""
function transformers_printall()
    docs = (storage = Pair{Symbol, Any}[],
            loader = Pair{Symbol, Any}[],
            writer = Pair{Symbol, Any}[])
    for ((type, name), doc) in TRANSFORMER_DOCUMENTATION
        if type ∈ (:storage, :loader, :writer)
            push!(getfield(docs, type), name => doc)
        else
            @warn "Documentation entry for $name gives invalid transformer type $type (should be 'storage', 'loader', or 'writer')"
        end
    end
    sort!.(values(docs), by = first)
    for type in (:storage, :loader, :writer)
        entries = getfield(docs, type)
        printstyled(" $type transformers ($(length(entries)))\n",
                    color=:blue, bold=true)
        for (name, doc) in entries
            printstyled("   • ", color=:blue)
            println(name)
        end
        type === :writer || print('\n')
    end
end

"""
    help_show(transformer::Symbol)

Show documentation of a particular data `transformer` (should it exist).

In the special case that `transformer` is `Symbol("")`, a list of all documented
transformers is printed.
"""
function help_show(transformer::Symbol)
    if transformer === Symbol("") # List all documented transformers
        transformers_printall()
    else
        tdocs = transformer_docs(transformer)
        if isnothing(tdocs)
            printstyled(" ! ", color=:red, bold=true)
            println("There is no documentation for the '$transformer' transformer")
        else
            display(tdocs)
        end
    end
end
