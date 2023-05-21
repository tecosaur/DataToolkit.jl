function load(::DataLoader{:passthrough}, from::T, ::Type{T}) where {T <: Any}
    from
end

function save(::DataWriter{:passthrough}, dest, info::Any)
    dest = info
end

function save(::DataWriter{:passthrough}, dest::IO, info::Any)
    write(dest, info)
end

supportedtypes(::Type{DataLoader{:passthrough}}, ::SmallDict{String, Any}, dataset::DataSet) =
    reduce(vcat, getproperty.(dataset.storage, :type)) |> unique

createpriority(::Type{DataLoader{:passthrough}}) = 20

create(::Type{DataLoader{:passthrough}}, source::String, dataset::DataSet) =
    any(isa.(dataset.storage, DataStorage{:raw}))

Store.shouldstore(::DataLoader{:passthrough}, ::Type) = false
