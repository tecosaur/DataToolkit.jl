import InteractiveUtils.edit

const EDIT_DOC = md"""
Edit the specification of a dataset

Open the specified dataset as a TOML file for editing,
and reload the dataset from the edited contents.

## Usage

    data> edit IDENTIFIER
"""

function deep_diff(old::Dict, new::Dict, parents::Vector{String}=String[])
    new_keys = setdiff(keys(new), keys(old))
    for key in sort(new_keys |> collect)
        print("  "^length(parents))
        printstyled(" + ", color=:light_green, bold=true)
        print("Added ")
        printstyled(key, '\n', color=:light_blue)
    end
    common_keys = keys(new) ∩ keys(old)
    for key in sort(common_keys |> collect)
        if new[key] != old[key]
            print("  "^length(parents))
            printstyled(" ~ ", color=:light_yellow, bold=true)
            print("Modified ")
            printstyled(key, color=:light_blue)
            print(":\n")
            deep_diff(old[key], new[key], vcat(parents, key))
        end
    end
    removed_keys = setdiff(keys(old), keys(new))
    for key in sort(removed_keys |> collect)
        print("  "^length(parents))
        printstyled(" - ", color=:light_red, bold=true)
        print("Removed ")
        printstyled(key, '\n', color=:light_blue)
    end
end

function deep_diff(old::Vector, new::Vector, parents::Vector{String}=String[])
    for (i, (o, n)) in enumerate(zip(old, new))
        if o != n
            print("  "^length(parents))
            printstyled(" ~ ", color=:light_yellow, bold=true)
            print("Modified ")
            printstyled('[', i, ']', color=:light_blue)
            print(":\n")
            deep_diff(o, n, vcat(parents, "[$i]"))
        end
    end
    if length(new) > length(old)
        print("  "^length(parents))
        printstyled(" + ", color=:light_green, bold=true)
        print("Added ")
        if length(new) - length(old) == 1
            printstyled('[', length(new), ']', '\n', color=:light_blue)
        else
            printstyled('[', length(old)+1, '-', length(new), ']',
                        '\n', color=:light_blue)
        end
    elseif length(new) < length(old)
        print("  "^length(parents))
        printstyled(" - ", color=:light_red, bold=true)
        print("Removed ")
        if length(old) - length(new) == 1
            printstyled('[', length(old), ']', '\n', color=:light_blue)
        else
            printstyled('[', length(new)+1, '-', length(old), ']',
                        '\n', color=:light_blue)
        end
    end
end

function deep_diff(old::Any, new::Any, parents::Vector{String}=String[])
    print("  "^length(parents), ' ')
    show(IOContext(stdout, :compact => true), old)
    printstyled(" ~> ", color=:light_yellow)
    show(IOContext(stdout, :compact => true), new)
    print('\n')
end

function repl_edit(input::AbstractString)
    if isempty(input)
        printstyled(" ! ", color=:yellow, bold=true)
        println("Specify a dataset to edit")
    else
        dataset = try resolve(input) catch _
            printstyled(" ! ", color=:red, bold=true)
            println("Could not resolve identifier: $input")
            return nothing
        end
        dataspec = convert(Dict, dataset)
        tomlfile = tempname(cleanup=false) * ".toml"
        open(tomlfile, "w") do io
            intermediate = IOBuffer()
            TOML.print(intermediate, Dict(dataset.name => [dataspec]))
            write(io, "data_config_version = ",
                  string(dataset.collection.version), '\n',
                  "#     ╭─[extracted from '$(dataset.collection.name)' for modification]\n",
                  "# ╭───┴────────────────────────$('─'^textwidth(dataset.name))──╮\n",
                  "# │ *Editing the definition of $(dataset.name)* │\n",
                  "# ╰────────────────────────────$('─'^textwidth(dataset.name))──╯\n\n")
            write(io, take!(DataToolkitBase.tomlreformat!(intermediate)))
        end
        edit(tomlfile, 8)
        isfile(tomlfile) || return nothing
        newspec = let tomldata = open(TOML.parse, tomlfile)
            dspecs = get(tomldata, dataset.name, Dict{String, Any}())
            if dspecs isa Vector && !isempty(dspecs) && first(dspecs) isa Dict
                first(dspecs)
            end
        end
        rm(tomlfile)
        newspec isa Dict || return nothing
        newspec isa Dict || return
        if newspec == dataspec
            printstyled("  No changes made\n", color=:light_black)
            return
        end
        deep_diff(dataspec, newspec)
        if !confirm_yn(" Does this look correct?")
            printstyled(" ! ", color=:red, bold=true)
            println("Cancelled")
            return nothing
        end
        index = findfirst(==(dataset), dataset.collection.datasets)
        newdata = DataSet(dataset.collection, dataset.name, newspec)
        newdata.collection.datasets[index] = newdata
        lintreport = LintReport(newdata)
        if !isempty(lintreport.results)
            show(lintreport)
            print("\n\n")
            DataToolkitBase.lintfix(lintreport)
        end
        write(newdata.collection)
        printstyled(" ✓ Edited '$(newdata.name)' ", color=:green)
        printstyled('(', newdata.uuid, ')', '\n', color=:light_black)
    end
end

completions(::ReplCmd{:edit}, sofar::AbstractString) =
    complete_dataset(sofar)
