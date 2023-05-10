# SmallDict implementation

SmallDict{K, V}() where {K, V} =
    SmallDict{K, V}(Vector{K}(), Vector{V}())
SmallDict() = SmallDict{Any, Any}()

SmallDict{K, V}(kv::Vector{<:Pair}) where {K, V} =
    SmallDict{K, V}(Vector{K}(first.(kv)), Vector{V}(last.(kv)))
SmallDict(kv::Vector{Pair{K, V}}) where {K, V} =
    SmallDict{K, V}(first.(kv), last.(kv))
SmallDict{K, V}(kv::Pair...) where {K, V} =
    SmallDict{K, V}(Vector{K}(first.(kv) |> collect),
                    Vector{V}(last.(kv) |> collect))
SmallDict(kv::Pair{K, V}...) where {K, V} = SmallDict{K, V}(kv...)
SmallDict(kv::Pair...) = SmallDict(collect(first.(kv)), collect(last.(kv)))

Base.convert(::Type{SmallDict{K, V}}, dict::Dict) where {K, V} =
    SmallDict{K, V}(Vector{K}(keys(dict) |> collect),
                    Vector{V}(values(dict) |> collect))
Base.convert(::Type{SmallDict}, dict::Dict{K, V}) where {K, V} =
    convert(SmallDict{K, V}, dict)

function smallify(dict::Dict{K, V}) where {K, V}
    stype(v) = v
    stype(::Type{Dict{Kv, Vv}}) where {Kv, Vv} = SmallDict{Kv, stype(Vv)}
    if V <: Dict || Dict <: V
        SmallDict{K, stype(V)}(Vector{K}(keys(dict) |> collect),
                               Vector{stype(V)}([
                                   if v isa Dict smallify(v) else v end
                                   for v in values(dict)]))
    else
        convert(SmallDict{K, V}, dict)
    end
end

Base.length(d::SmallDict) = length(d.keys)
Base.keys(d::SmallDict) = d.keys
Base.values(d::SmallDict) = d.values

Base.iterate(d::SmallDict, index=1) = if index <= length(d)
    (d.keys[index] => d.values[index], index+1)
end

function Base.get(d::SmallDict{K}, key::K, default) where {K}
    @inbounds for (i, k) in enumerate(d.keys)
        k == key && return d.values[i]
    end
    default
end

function Base.setindex!(d::SmallDict{K, V}, value::V, key::K) where {K, V}
    @inbounds for (i, k) in enumerate(d.keys)
        if k == key
            d.values[i] = value
            return d
        end
    end
    push!(d.keys, key)
    push!(d.values, value)
    d
end

function Base.delete!(d::SmallDict{K}, key::K) where {K}
    @inbounds for (i, k) in enumerate(d.keys)
        if k == key
            deleteat!(d.keys, i)
            deleteat!(d.values, i)
            return d
        end
    end
    d
end

function Base.sizehint!(d::SmallDict, size::Integer)
    sizehint!(d.keys, size)
    sizehint!(d.values, size)
end

Base.empty(::SmallDict{K, V}) where {K, V} = SmallDict{K, V}()

function Base.empty!(d::SmallDict{K, V}) where {K, V}
    d.keys = Vector{K}()
    d.values = Vector{V}()
    d
end
