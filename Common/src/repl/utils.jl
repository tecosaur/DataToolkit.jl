function complete_collection(sofar::AbstractString)
    name_matches = filter(c -> startswith(c.name, sofar), STACK)
    if !isempty(name_matches)
        getproperty.(name_matches, :name)
    else
        uuid_matches = filter(c -> startswith(string(c.uuid), sofar), STACK)
        getproperty.(uuid_matches, :name)
    end |> Vector{String}
end

function complete_dataset(sofar::AbstractString)
    try # In case `resolve` or `getlayer` fail.
        relevant_options = if !isnothing(match(r"^.+::", sofar))
            identifier = parse(Identifier, first(split(sofar, "::")))
            types = map(l -> l.type, resolve(identifier).loaders) |>
                Iterators.flatten .|> string |> unique
            string.(string(identifier), "::", types)
        elseif !isnothing(match(r"^[^:]+:", sofar))
            layer, _ = split(sofar, ':', limit=2)
            filter(o -> startswith(o, sofar),
                   string.(layer, ':',
                           unique(getproperty.(
                               DataToolkitBase.getlayer(layer).datasets, :name))))
        else
            filter(o -> startswith(o, sofar),
                   vcat(getproperty.(STACK, :name) .* ':',
                        getproperty.(DataToolkitBase.getlayer(nothing).datasets, :name) |> unique))
        end
    catch _
        String[]
    end |> options -> sort(filter(o -> startswith(o, sofar), options), by=natkeygen)
end

"""
    confirm_stack_nonempty(; quiet::Bool=false)
Return `true` if STACK is non-empty.

Unless `quiet` is set, should the stack be empty a warning message is emmited.
"""
confirm_stack_nonempty(; quiet::Bool=false) =
    !isempty(STACK) || begin
        if !quiet
            printstyled(" ! ", color=:red, bold=true)
            println("The data collection stack is empty")
        end
        false
    end

"""
    confirm_stack_first_writable(; quiet::Bool=false)
First call `confirm_stack_nonempty` then return `true` if the first collection
of STACK is writable.

Unless `quiet` is set, should this not be the case a warning message is emmited.
"""
confirm_stack_first_writable(; quiet::Bool=false) =
    confirm_stack_nonempty(; quiet) &&
    (iswritable(first(STACK)) || begin
        if !quiet
            printstyled(" ! ", color=:red, bold=true)
            println("The first item on the data collection stack is not writable")
        end
        false
    end)
