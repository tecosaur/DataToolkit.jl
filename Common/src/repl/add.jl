const ADD_DOC = md"""
Add a data set to the current collection

## Usage

This will interactively ask for all required information.

Optionally, the *name* and *source* can be specified using the following forms:

    data> add NAME
    data> add NAME from SOURCE
    data> add from SOURCE

As a shorthand, `f` can be used instead of `from`.

The transformers drivers used can also be specified by using a `via` argument
before `from`, with a form like so:

    data> add via TRANSFORMERS...
    data> add NAME via TRANSFORMERS... from SOURCE

The *type* of transformer can also be specified using flags. Namely storage (`-s`),
loader (`-l`), and writer (`-w`). For example:

    data> add via -s web -l csv

Invalid transformer drivers are automatically skipped, so one could use:

    data> add via -sl web csv

which would be equivalent to `add via -s web csv -l web csv`, but only `web`
will be reccognised as a valid storage backend and `csv` as a valid loader.
This works well in most cases, which is why `-sl` are the default flags.

## Examples

    data> add iris from https://github.com/mwaskom/seaborn-data/blob/master/iris.csv
    data> add iris via web csv from https://github.com/mwaskom/seaborn-data/blob/master/iris.csv
    data> add iris via -s web -l csv from https://github.com/mwaskom/seaborn-data/blob/master/iris.csv
    data> add \"from\" from.txt # add a data set with the name from
"""

function add(input::AbstractString)
    confirm_stack_nonempty() || begin
        printstyled(" i ", color=:cyan, bold=true)
        println("Consider creating a data collection first with 'init'")
        return nothing
    end
    confirm_stack_first_writable() || return nothing
    name, rest = if isnothing(match(r"^(?:v|via|f|from)\b|^\s*$|^https?://", input)) &&
        !isfile(first(peelword(input)))
        peelword(input)
    else
        prompt(" Name: "), String(input)
    end
    if name in getproperty.(first(STACK).datasets, :name)
        confirm_yn(" '$name' names an existing data set, continue anyway?", false) ||
            return nothing
        printstyled(" i ", color=:cyan, bold=true)
        println("Consider setting additional attributes to disambiguate")
    end
    via = (; storage = Symbol[],
           loaders = Symbol[],
           writers = Symbol[])
    if first(peelword(rest)) ∈ ("v", "via")
        targets = [:storage, :loaders]
        while !isempty(rest) && first(peelword(rest)) ∉ ("f", "from")
            viarg, rest = peelword(rest)
            if first(viarg) == '-'
                targets = []
                's' in viarg && push!(targets, :storage)
                'l' in viarg && push!(targets, :loaders)
                'w' in viarg && push!(targets, :writers)
            else
                push!.(getfield.(Ref(via), targets), Symbol(viarg))
            end
        end
    else
        push!(via.storage, :*)
        push!(via.loaders, :*)
    end
    from = if first(peelword(rest)) ∈ ("f", "from")
        last(peelword(rest))
    elseif !isempty(rest)
        rest
    else
        prompt(" From: ", allowempty=true)
    end
    spec = prompt_attributes()
    DataToolkitBase.add(DataSet, name, spec, from; via...)
end

"""
    prompt_attributes() -> Dict{String, Any}

Interactively prompt for a description and other arbitrary attributes, with
values interpreted using `TOML.parse`.
"""
function prompt_attributes()
    spec = Dict{String, Any}()
    description = prompt(" Description: ", allowempty=true)
    if !isempty(description)
        spec["description"] = description
    end
    while (attribute = prompt(" [Attribute]: ", allowempty=true)) |> !isempty
        print("\e[A\e[G\e[K")
        value = prompt(" $attribute: ")
        if isnothing(match(r"^true|false|[.\d]+|\".*\"|\[.*\]|\{.*\}$", value))
            value = string('"', value, '"')
        end
        spec[attribute] = TOML.parse(string("value = ", value))["value"]
    end
    print("\e[A\e[G\e[K")
    spec
end
