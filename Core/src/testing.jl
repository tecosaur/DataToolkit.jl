push!(PLUGINS,
    Plugin("test",
        [function (collection::DataCollection, func::typeof(identity), args, kwargs)
             @info "Calling $func on collection $(collection.name)"
             (collection, func, args, kwargs)
         end,
         function (C::Type{DataCollection}, func::typeof(fromtoml),
                   args::Tuple{Dict}, kwargs)
             @info "Loading DataCollection from Dict"
             (C, func, args, kwargs)
         end,]))

push!(PLUGINS, Plugin("backwards", [
    function (loader::DataLoader{:dump}, func::typeof(load), args, kwargs)
        (loader, reverse ∘ func, args, kwargs)
    end]))

function fromstorage(storer::DataStorage{:file}, ::Type{IOStream})
    file = storer.arguments["path"]
    open(file, "r")
end

function load(::DataLoader{:dump}, from::IOStream, ::Type{String})
    read(from, String)
end
