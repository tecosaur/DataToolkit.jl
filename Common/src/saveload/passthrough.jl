function load(::DataLoader{:passthrough}, from::T, ::Type{T}) where {T <: Any}
    from
end

function save(::DataWriter{:passthrough}, dest, info::Any)
    dest = info
end

function save(::DataWriter{:passthrough}, dest::IO, info::Any)
    write(dest, info)
end

supportedtypes(::Type{DataLoader{:passthrough}}, _::Dict{String, Any}, dataset::DataSet) =
    reduce(vcat, getproperty.(dataset.storage, :support)) |> unique
