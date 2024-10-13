function Base.show(io::IO, ::MIME"text/plain", dsi::Identifier)
    collection = get(io, :data_collection, nothing)
    printstyled(io, if isnothing(dsi.collection)
                    '□'
                elseif !isempty(STACK) && ((dsi.collection isa UUID && dsi.collection == first(STACK).uuid) ||
                    (dsi.collection isa AbstractString && dsi.collection == first(STACK).name))
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

function Base.show(io::IO, dt::DataTransformer{kind, driver}) where {kind, driver}
    @nospecialize
    dtt = typeof(dt)
    get(io, :omittype, false) || print(io, "Data", titlecase(String(kind)), '{')
    printstyled(io, driver, color=:green)
    get(io, :omittype, false) || print(io, '}')
    print(io, "(")
    for qtype in dt.type
        type = typeify(qtype, mod=dt.dataset.collection.mod)
        if !isnothing(type)
            printstyled(io, type, color=:yellow)
        else
            printstyled(io, qtype.name, color=:yellow)
            if !isempty(qtype.parameters)
                printstyled(io, '{', join(string.(qtype.parameters), ','), '}',
                            color=:yellow)
            end
        end
        qtype === last(dt.type) || print(io, ", ")
    end
    print(io, ")")
end

function Base.show(io::IO, ::MIME"text/plain", a::Advice)
    print(io, "Advice($(a.f))")
end

function Base.show(io::IO, p::Plugin)
    print(io, "Plugin(")
    show(io, p.name)
    print(io, ", [")
    function context(a::Advice)
        validmethods = methods(a.f, Tuple{Function, Any, Vararg{Any}})
        if length(validmethods) === 0
            string(a.f)
        else
            context = first(validmethods).sig.types[3:end]
            string(a.f, '(', join(context, ", "), ')')
        end
    end
    join(io, map(context, p.advisors), ", ")
    print(io, "])")
end

function Base.show(io::IO, dta::AdviceAmalgamation)
    get(io, :omittype, false) || print(io, "AdviceAmalgamation(")
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
    dsets = sort(datacollection.datasets, by = d -> natkeygen(d.name))
    drows = first(displaysize(io)) - 4
    if length(dsets) <=drows
        for dataset in dsets
            print(io, "\n     ")
            show(IOContext(io, :compact => true), dataset)
        end
    else
        drows -= 4 + drows ÷ 5
        for dataset in dsets[1:drows÷2]
            print(io, "\n     ")
            show(IOContext(io, :compact => true), dataset)
        end
        printstyled(io, "\n     ⋮", color = :light_black)
        printstyled(io, "\n     $(length(dsets)-drows) datasets omitted",
                    color = :light_black, italic = true)
        printstyled(io, "\n     ⋮", color = :light_black)
        for dataset in dsets[end-drows÷2:end]
            print(io, "\n     ")
            show(IOContext(io, :compact => true), dataset)
        end
    end
end
