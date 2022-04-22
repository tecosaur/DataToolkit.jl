function displaytable(rows::Vector{<:Vector}; spacing::Integer=2)
    column_widths =
        maximum.(textwidth.(string.(getindex.(rows, i)))
                 for i in 1:length(rows[1]))
    map(rows) do row
        join([rpad(col, width) for (col, width) in zip(row, column_widths)],
             ' '^spacing)
    end
end

function displaytable(headers::Vector, rows::Vector{<:Vector};
                      spacing::Integer=2)
    rows = displaytable(vcat([headers], rows); spacing)
    rule = '─'^length(rows[1])
    vcat("\e[1m" * rows[1] * "\e[0m", rule, rows[2:end])
end

function Base.show(io::IO, dsi::Identifier)
    printstyled(io, something(dsi.collection, "■"), ':', color=:magenta)
    print(io, dsi.dataset)
    # if !isnothing(dsi.version)
    #     printstyled(io, '@', color=:cyan)
    #     if dsi.version isa VersionNumber
    #         printstyled(io, 'v', color=:cyan)
    #     end
    #     printstyled(io, dsi.version, color=:cyan)
    # end
    # if !isnothing(dsi.hash)
    #     printstyled(io, '#', string(dsi.hash, base=16), color=:light_black)
    # end
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
    for qtype in adt.supports
        printstyled(io, qtype.name, color=:yellow)
        qtype === last(adt.supports) || print(io, ", ")
    end
    print(io, ")")
end

function Base.show(io::IO, ::MIME"text/plain", ::DataAdvice{C, F}) where {C, F}
    print(io, "DataAdvice{$C, $F}")
end

function Base.show(io::IO, p::Plugin)
    print(io, "Plugin(")
    show(io, p.name)
    print(io, ", [")
    context(::DataAdvice{C, F}) where {C, F} = (C, F)
    print(io, join(string.(context.(p.advisers)), ", "))
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
        qtypes = vcat(getfield.(dataset.loaders, :supports)...) |> unique
        for qtype in qtypes
            printstyled(io, qtype.name, color=:yellow)
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
    if !isnothing(datacollection.path)
        printstyled(io, " (writable)", color=:light_black)
    end
    if !isempty(datacollection.plugins)
        print(io, "\n  Plugins: ")
        show(IOContext(io, :compact => true, :omittype => true),
             datacollection.advise)
    end
    print(io, "\n  Stores: ", join(getfield.(datacollection.stores, :name), ", "))
    print(io, "\n  Data sets:")
    for dataset in datacollection.datasets
        print(io, "\n     ")
        show(IOContext(io, :compact => true), dataset)
    end
end
