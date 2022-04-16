function Base.show(io::IO, dsi::Identifier)
    if !isnothing(dsi.layer)
        printstyled(io, dsi.layer, ':', color=:magenta)
    end
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
        printstyled(io, "::", dsi.type, color=:yellow)
    end
end

function Base.show(io::IO, adt::AbstractDataTransformer)
    adtt = typeof(adt)
    printstyled(io, first(adtt.parameters), color=:green)
    get(io, :omittype, false) || print(io, ' ', nameof(adtt))
    if adt isa DataStorage
        return
    end
    print(io, " (")
    for qtype in adt.supports
        printstyled(io, qtype.name, color=:yellow)
        qtype === last(adt.supports) || print(io, ", ")
    end
    print(io, ')')
end

function Base.show(io::IO, dta::DataTransducerAmalgamation)
    get(io, :omittype, false) || print(io, "DataTransducerAmalgamation(")
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
    print(io, "DataSet: ")
    if !isnothing(dataset.collection.name)
        printstyled(io, dataset.collection.name, color=:magenta)
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
    if !isnothing(datacollection.writer)
        printstyled(io, " (writable)", color=:light_black)
    end
    if !isempty(datacollection.plugins)
        print(io, "\n  Plugins: ")
        show(IOContext(io, :compact => true, :omittype => true),
             datacollection.transduce)
    end
    print(io, "\n  Stores: ", join(getfield.(datacollection.stores, :name), ", "))
    print(io, "\n  Data sets:")
    for dataset in datacollection.datasets
        print(io, "\n     ")
        show(IOContext(io, :compact => true), dataset)
    end
end
