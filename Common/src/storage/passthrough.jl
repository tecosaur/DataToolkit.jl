getstorage(storage::DataStorage{:passthrough}, T::Type) =
    read(resolve(Identifier(get(storage, "source"))), T)

createpriority(::Type{<:DataStorage{:passthrough}}) = 60

function create(::Type{<:DataStorage{:passthrough}}, source::String)
    if try resolve(parse(Identifier, source)); true catch _ false end
        Dict{String, Any}("source" => source)
    end
end

# TODO putstorage
