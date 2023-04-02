function displaytable(rows::Vector{<:Vector};
                      spacing::Integer=2, maxwidth::Int=80)
    column_widths =
        maximum.(textwidth.(string.(getindex.(rows, i)))
                 for i in 1:length(rows[1]))
    table_width = sum(column_widths) + spacing * length(column_widths)
    if sum(column_widths) > maxwidth
        column_widths = max.(1, floor.(Int, column_widths .* maxwidth/table_width))
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

function displaytable(headers::Vector, rows::Vector{<:Vector};
                      spacing::Integer=2, maxwidth::Int=80)
    rows = displaytable(vcat([headers], rows); spacing, maxwidth)
    rule = '─'^length(rows[1])
    vcat("\e[1m" * rows[1] * "\e[0m", rule, rows[2:end])
end

function Base.show(io::IO, ::MIME"text/plain", dsi::Identifier;
                   collection::Union{DataCollection, Nothing}=nothing)
    printstyled(io, if isnothing(dsi.collection)
                    '□'
                elseif !isempty(STACK) && (dsi.collection isa UUID && dsi.collection == first(STACK).uuid) ||
                    (dsi.collection isa AbstractString && dsi.collection == first(STACK).name)
                    '■'
                else
                    dsi.collection
                end,
                ':', color=:magenta)
    if isnothing(collection)
        print(io, dsi.dataset)
    else
        dname = string(dsi.dataset)
        nameonly = Identifier(nothing, dsi.dataset, nothing, dsi.parameters)
        namestr = @advise collection string(nameonly)
        if startswith(namestr, dname)
            print(io, dsi.dataset)
            printstyled(io, namestr[nextind(namestr, length(dname)):end],
                        color=:cyan)
        else
            print(io, namestr)
        end
    end
    if !isnothing(dsi.type)
        printstyled(io, "::", string(dsi.type), color=:yellow)
    end
end

function Base.show(io::IO, adt::AbstractDataTransformer)
    adtt = typeof(adt)
    get(io, :omittype, false) || print(io, nameof(adtt), '{')
    printstyled(io, first(adtt.parameters), color=:green)
    get(io, :omittype, false) || print(io, '}')
    print(io, "(")
    for qtype in adt.type
        type = typeify(qtype, mod=adt.dataset.collection.mod)
        if !isnothing(type)
            printstyled(io, type, color=:yellow)
        else
            printstyled(io, qtype.name, color=:yellow)
            if !isempty(qtype.parameters)
                printstyled(io, '{', join(string.(qtype.parameters), ','), '}',
                            color=:yellow)
            end
        end
        qtype === last(adt.type) || print(io, ", ")
    end
    print(io, ")")
end

function Base.show(io::IO, ::MIME"text/plain", ::DataAdvice{F, C}) where {F, C}
    print(io, "DataAdvice{$F, $C}")
end

function Base.show(io::IO, p::Plugin)
    print(io, "Plugin(")
    show(io, p.name)
    print(io, ", [")
    context(::DataAdvice{F, C}) where {F, C} = (F, C)
    print(io, join(string.(context.(p.advisors)), ", "))
    print(io, "])")
end

function Base.show(io::IO, dta::DataAdviceAmalgamation)
    get(io, :omittype, false) || print(io, "DataAdviceAmalgamation(")
    for plugin in dta.plugins_wanted
        if plugin in dta.plugins_used
            print(io, plugin, ' ')
            printstyled(io, '✔', color = :green)
        else
            printstyled(io, plugin, ' ', color = :light_black)
            printstyled(io, '✘', color = :red)
        end
        plugin === last(dta.plugins_wanted) || print(io, ", ")
    end
    get(io, :omittype, false) || print(io, ")")
end

function Base.show(io::IO, dataset::DataSet)
    if get(io, :compact, false)
        printstyled(io, dataset.name, color=:blue)
        print(io, " (")
        qtypes = vcat(getfield.(dataset.loaders, :type)...) |> unique
        for qtype in qtypes
            type = typeify(qtype, mod=dataset.collection.mod)
            if !isnothing(type)
                printstyled(io, type, color=:yellow)
            else
                printstyled(io, qtype.name, color=:yellow)
                if !isempty(qtype.parameters)
                    printstyled(io, '{', join(string.(qtype.parameters), ','), '}',
                                color=:yellow)
                end
            end
            qtype === last(qtypes) || print(io, ", ")
        end
        print(io, ')')
        return
    end
    print(io, "DataSet ")
    if !isnothing(dataset.collection.name)
        color = if length(STACK) > 0 && dataset.collection === first(STACK)
            :light_black
        else
            :magenta
        end
        printstyled(io, dataset.collection.name; color)
        printstyled(io, ':', color=:light_black)
    end
    printstyled(io, dataset.name, bold=true, color=:blue)
    for (label, field) in [("Storage", :storage),
                           ("Loaders", :loaders),
                           ("Writers", :writers)]
        entries = getfield(dataset, field)
        if !isempty(entries)
            print(io, "\n  ", label, ": ")
            for entry in entries
                show(IOContext(io, :compact => true, :omittype => true), entry)
                entry === last(entries) || print(io, ", ")
            end
        end
    end
end

function Base.show(io::IO, datacollection::DataCollection)
    if get(io, :compact, false)
        printstyled(io, datacollection.name, color=:magenta)
        return
    end
    print(io, "DataCollection:")
    if !isnothing(datacollection.name)
        printstyled(io, ' ', datacollection.name, color=:magenta)
    end
    if iswritable(datacollection)
        printstyled(io, " (writable)", color=:light_black)
    elseif get(datacollection, "locked", false) === true
        printstyled(io, " (locked)", color=:light_black)
    end
    if !isempty(datacollection.plugins)
        print(io, "\n  Plugins: ")
        show(IOContext(io, :compact => true, :omittype => true),
             datacollection.advise)
    end
    print(io, "\n  Data sets:")
    for dataset in sort(datacollection.datasets, by = d -> natkeygen(d.name))
        print(io, "\n     ")
        show(IOContext(io, :compact => true), dataset)
    end
end
