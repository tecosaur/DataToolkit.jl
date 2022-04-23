function load(::DataLoader{:passthrough}, from::Any, ::Type{<:Any})
    from
end

function save(::DataWriter{:passthrough}, dest, info::Any)
    dest = info
end
