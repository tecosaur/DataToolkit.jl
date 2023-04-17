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

function create(::Type{DataLoader{:passthrough}}, source::String, dataset::DataSet)
    if any(isa.(dataset.storage, DataStorage{:raw}))
        Dict{String, Any}()
    end
end
