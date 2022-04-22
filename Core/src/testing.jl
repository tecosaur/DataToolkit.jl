# push!(PLUGINS,
#     Plugin("test",
#         [function (collection::DataCollection, func::typeof(identity), args, kwargs)
#              @info "Calling $func on collection $(collection.name)"
#              (collection, func, args, kwargs)
#          end,
#          function (C::Type{DataCollection}, func::typeof(fromspec),
#                    args::Tuple{Dict}, kwargs)
#              @info "Loading DataCollection from Dict"
#              (C, func, args, kwargs)
#          end,]))

# push!(PLUGINS, Plugin("backwards", [
#     function (loader::DataLoader{:dump}, func::typeof(load), args, kwargs)
#         (loader, reverse ∘ func, args, kwargs)
#     end,
#     function (writer::DataLoader{:dump}, func::typeof(save), args, kwargs)
#         reverse_info(w, t, i) = (w, t, reverse(i))
#         (writer, func ∘ reverse_info, args, kwargs)
#     end,
# ]))

rot13(c::Char) = c + if !isletter(c) 0 elseif uppercase(c) < 'N' 13 else -13 end
rot13(s::String) = map(rot13, s)

push!(PLUGINS, Plugin("rot13", [
    function (post::Function, func::typeof(load), loader::DataLoader{:dump}, from, as::Type)
        (if get(loader.dataset.parameters, "rot13", false)
             rot13 ∘ post else post end,
         func,
         (loader, from, as))
    end,
    function (post::Function, func::typeof(save), writer::DataWriter{:dump}, target, info::AbstractString)
        if get(writer.dataset.parameters, "rot13", false)
            (post, func, (writer, target, rot13(info)))
        else
            (post, func, (writer, target, info))
        end
    end,
]))

# function storage(storage::DataStorage{:filesystem}, ::Type{IOStream}; write::Bool=false)
#     file = storage.parameters["path"]
#     open(file; write)
# end

function load(::DataLoader{:dump}, from::IOStream, ::Type{String})
    result = read(from, String)
    close(from)
    result
end

function save(::DataWriter{:dump}, to::IOStream, info::AbstractString)
    write(to, info)
    close(to)
end

# function load(::DataLoader{:passthrough}, from::Any, ::Type{Any})
#     from
# end
