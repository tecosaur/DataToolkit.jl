struct InventoryFile
    path::String
    recency::Float64 # mtime
end

mutable struct InventoryConfig
    max_age::Int
end

struct CollectionInfo
    uuid::UUID
    path::Union{String, Nothing}
    name::Union{String, Nothing}
    seen::DateTime
end

struct SourceInfo
    recipe::UInt64
    references::Vector{UUID}
    accessed::DateTime
    checksum::Union{Nothing, Tuple{Symbol, Unsigned}}
    type::Union{Nothing, Tuple{QualifiedType, UInt64}}
    extension::String
end

struct Inventory
    file::InventoryFile
    config::InventoryConfig
    collections::Vector{CollectionInfo}
    sources::Vector{SourceInfo}
end

≃(a::CollectionInfo, b::CollectionInfo) = a.uuid == b.uuid
≃(a::DataCollection, b::CollectionInfo) = a.uuid == b.uuid
≃(a::CollectionInfo, b::DataCollection) = b ≃ a

function ≃(a::SourceInfo, b::SourceInfo)
    a.recipe == b.recipe &&
        a.checksum == b.checksum &&
        a.extension == b.extension
end
