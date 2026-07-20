const EDIT_DOC = md"""
Edit the specification of a dataset

Open the specified dataset as a TOML file for editing,
and reload the dataset from the edited contents.

## Usage

    data> edit IDENTIFIER
"""

function deep_diff(io::IO, old::AbstractDict, new::AbstractDict, parents::Vector{String}=String[])
    new_keys = setdiff(keys(new), keys(old))
    for key in sort(new_keys |> collect)
        print(io, "  "^length(parents))
        printstyled(io, " + ", color=:light_green, bold=true)
        print(io, "Added ")
        printstyled(io, key, '\n', color=:light_blue)
    end
    common_keys = keys(new) ∩ keys(old)
    for key in sort(common_keys |> collect)
        if new[key] != old[key]
            print(io, "  "^length(parents))
            printstyled(io, " ~ ", color=:light_yellow, bold=true)
            print(io, "Modified ")
            printstyled(io, key, color=:light_blue)
            print(io, ":\n")
            deep_diff(io, old[key], new[key], vcat(parents, key))
        end
    end
    removed_keys = setdiff(keys(old), keys(new))
    for key in sort(removed_keys |> collect)
        print(io, "  "^length(parents))
        printstyled(io, " - ", color=:light_red, bold=true)
        print(io, "Removed ")
        printstyled(io, key, '\n', color=:light_blue)
    end
end

function deep_diff(io::IO, old::Vector, new::Vector, parents::Vector{String}=String[])
    for (i, (o, n)) in enumerate(zip(old, new))
        if o != n
            print(io, "  "^length(parents))
            printstyled(io, " ~ ", color=:light_yellow, bold=true)
            print(io, "Modified ")
            printstyled(io, '[', i, ']', color=:light_blue)
            print(io, ":\n")
            deep_diff(io, o, n, vcat(parents, "[$i]"))
        end
    end
    if length(new) > length(old)
        print(io, "  "^length(parents))
        printstyled(io, " + ", color=:light_green, bold=true)
        print(io, "Added ")
        if length(new) - length(old) == 1
            printstyled(io, '[', length(new), ']', '\n', color=:light_blue)
        else
            printstyled(io, '[', length(old)+1, '-', length(new), ']',
                        '\n', color=:light_blue)
        end
    elseif length(new) < length(old)
        print(io, "  "^length(parents))
        printstyled(io, " - ", color=:light_red, bold=true)
        print(io, "Removed ")
        if length(old) - length(new) == 1
            printstyled(io, '[', length(old), ']', '\n', color=:light_blue)
        else
            printstyled(io, '[', length(new)+1, '-', length(old), ']',
                        '\n', color=:light_blue)
        end
    end
end

function deep_diff(io::IO, old::Any, new::Any, parents::Vector{String}=String[])
    print(io, "  "^length(parents), ' ')
    show(IOContext(io, :compact => true), old)
    printstyled(io, " ~> ", color=:light_yellow)
    show(IOContext(io, :compact => true), new)
    print(io, '\n')
end

function repl_edit(io::IO, input::AbstractString)
    if all(isspace, input)
        printstyled(io, " ! ", color=:yellow, bold=true)
        println(io, "Specify a DataSet to edit")
        return
    end
    dataset = try resolve(input) catch err
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
    refresh!(dataset.collection)
    dataspec = convert(Dict, dataset)
    tomlfile = tempname(cleanup=false) * ".toml"
    open(tomlfile, "w") do file
        datakeygen(key) = if haskey(DataToolkitCore.DATA_CONFIG_KEY_SORT_MAPPING, key)
            [DataToolkitCore.DATA_CONFIG_KEY_SORT_MAPPING[key]]
        else natkeygen(key) end
        intermediate = IOBuffer()
        TOML.print(intermediate, Dict(dataset.name => [dataspec]),
                    sorted = true, by = datakeygen)
        write(file, "data_config_version = ",
                string(dataset.collection.version), '\n',
                "#     ╭─[extracted from '$(dataset.collection.name)' for modification]\n",
                "# ╭───┴────────────────────────$('─'^textwidth(dataset.name))──╮\n",
                "# │ *Editing the definition of $(dataset.name)* │\n",
                "# ╰────────────────────────────$('─'^textwidth(dataset.name))──╯\n\n")
        write(file, take!(DataToolkitCore.tomlreformat!(intermediate)))
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
        printstyled(io, "  No changes made\n", color=:light_black)
        return
    end
    deep_diff(io, dataspec, newspec)
    if !confirm_yn(io, " Does this look correct?")
        printstyled(io, " ! ", color=:red, bold=true)
        println(io, "Cancelled")
        return
    end
    index = findfirst(==(dataset), dataset.collection.datasets)
    newdata = DataSet(dataset.collection, dataset.name, newspec)
    newdata.collection.datasets[index] = newdata
    lintreport = LintReport(newdata)
    if !isempty(lintreport.results)
        show(io, MIME("text/plain"), lintreport)
        print(io, "\n\n")
        DataToolkitCore.lintfix(lintreport)
    end
    save!(newdata.collection)
    printstyled(io, " ✓ Edited '$(newdata.name)' ", color=:green)
    printstyled(io, '(', newdata.uuid, ')', '\n', color=:light_black)
end
