getstorage(storage::DataStorage{:passthrough}, T::Type) =
    read(resolve(Identifier(get(storage, "ident"))), T)

createpriority(::Type{<:DataStorage{:passthrough}}) = 60

function create(::Type{<:DataStorage{:passthrough}}, source::String)
    if try resolve(parse(Identifier, source)); true catch _ false end
        Dict{String, Any}("ident" => source)
    end
end

# TODO putstorage
