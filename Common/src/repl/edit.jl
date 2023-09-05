import InteractiveUtils.edit

const EDIT_DOC = md"""
Edit the specification of a dataset

Open the specified dataset as a TOML file for editing,
and reload the dataset from the edited contents.

## Usage

    data> edit IDENTIFIER
"""

function deep_diff(old::AbstractDict, new::AbstractDict, parents::Vector{String}=String[])
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
    if all(isspace, input)
        printstyled(" ! ", color=:yellow, bold=true)
        println("Specify a DataSet to remove")
        return
    end
    dataset = try resolve(input) catch err
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
    if !iswritable(dataset.collection)
        printstyled(" ! ", color=:red, bold=true)
        println("The data collection $(dataset.name) belongs to is read-only")
        return
    end
    dataspec = convert(Dict, dataset)
    tomlfile = tempname(cleanup=false) * ".toml"
    open(tomlfile, "w") do io
        datakeygen(key) = if haskey(DataToolkitBase.DATA_CONFIG_KEY_SORT_MAPPING, key)
            [DataToolkitBase.DATA_CONFIG_KEY_SORT_MAPPING[key]]
        else natkeygen(key) end
        intermediate = IOBuffer()
        TOML.print(intermediate, Dict(dataset.name => [dataspec]),
                    sorted = true, by = datakeygen)
        write(io, "data_config_version = ",
                string(dataset.collection.version), '\n',
                "#     ╭─[extracted from '$(dataset.collection.name)' for modification]\n",
                "# ╭───┴────────────────────────$('─'^textwidth(dataset.name))──╮\n",
                "# │ *Editing the definition of $(dataset.name)* │\n",
                "# ╰────────────────────────────$('─'^textwidth(dataset.name))──╯\n\n")
        write(io, take!(DataToolkitBase.tomlreformat!(intermediate)))
    end
    edit(tomlfile, 8)
    isfile(tomlfile) || return
    newspec = let tomldata = open(TOML.parse, tomlfile)
        dspecs = get(tomldata, dataset.name, Dict{String, Any}())
        if dspecs isa Vector && !isempty(dspecs) && first(dspecs) isa Dict
            first(dspecs)
        end
    end
    rm(tomlfile)
    newspec isa Dict || return
    if newspec == dataspec
        printstyled("  No changes made\n", color=:light_black)
        return
    end
    deep_diff(dataspec, newspec)
    if !confirm_yn(" Does this look correct?")
        printstyled(" ! ", color=:red, bold=true)
        println("Cancelled")
        return
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

completions(::ReplCmd{:edit}, sofar::AbstractString) =
    complete_dataset(sofar)
