function load(::DataLoader{:passthrough}, from::Any, ::Type{<:Any})
    from
end

function save(::DataWriter{:passthrough}, dest, info::Any)
    dest = info
end

function save(::DataWriter{:passthrough}, dest::IO, info::Any)
    write(dest, info)
end
