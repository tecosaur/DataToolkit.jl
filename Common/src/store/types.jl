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

abstract type SourceInfo end

struct StoreSource <: SourceInfo
    recipe::UInt64
    references::Vector{UUID}
    accessed::DateTime
    checksum::Union{Nothing, Tuple{Symbol, Unsigned}}
    extension::String
end

struct CacheSource <: SourceInfo
    recipe::UInt64
    references::Vector{UUID}
    accessed::DateTime
    type::QualifiedType
    typehash::UInt64
    packages::Vector{Base.PkgId}
end

struct Inventory
    file::InventoryFile
    config::InventoryConfig
    collections::Vector{CollectionInfo}
    stores::Vector{StoreSource}
    caches::Vector{CacheSource}
end

≃(a::CollectionInfo, b::CollectionInfo) = a.uuid == b.uuid
≃(a::DataCollection, b::CollectionInfo) = a.uuid == b.uuid
≃(a::CollectionInfo, b::DataCollection) = b ≃ a

≃(a::SourceInfo, b::SourceInfo) = false
≃(a::StoreSource, b::StoreSource) =
    a.recipe == b.recipe && a.checksum == b.checksum &&
    a.extension == b.extension
≃(a::CacheSource, b::CacheSource) =
    a.recipe == b.recipe && a.typehash == b.typehash
