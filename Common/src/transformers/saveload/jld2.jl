function load(loader::DataLoader{:jld2}, from::FilePath, R::Type)
    @import JLD2
    key = get(loader, "key", nothing)
    if isnothing(key)
        @assert R == Dict{String, Any}
        JLD2.load(from.path)
    elseif key isa String
        JLD2.load(from.path, key)::R
    elseif key isa Vector
        JLD2.load(from.path, key...)::R
    else
        error("JLD2 key is of unsupported form: $(typeof(key)).")
    end
end

supportedtypes(::Type{DataLoader{:jld2}}, spec::SmallDict{String, Any}) =
    [QualifiedType(if haskey(spec, "key") Any else Dict{String, Any} end)]

function save(::DataLoader{:jld2}, info::Dict{String, Any}, dest::FilePath)
    @import JLD2
    JLD2.save(dest.path, info)
end

createpriority(::Type{DataLoader{:jld2}}) = 10

create(::Type{DataLoader{:jld2}}, source::String) =
    !isnothing(match(r"\.jld2$"i, source))

Store.shouldstore(::DataLoader{:jld2}, ::Type) = false
