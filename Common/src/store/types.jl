struct InventoryFile
    path::String
    recency::Float64 # mtime
    writable::Bool
end

mutable struct InventoryConfig
    auto_gc::Int
    max_age::Union{Int, Nothing}  # Days
    max_size::Union{Int, Nothing} # Bytes
    recency_beta::Number
    store_dir::String
    cache_dir::String
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
    checksum::Union{Nothing, Tuple{Symbol, String}}
    extension::String
end

struct CacheSource <: SourceInfo
    recipe::UInt64
    references::Vector{UUID}
    accessed::DateTime
    types::Vector{Pair{QualifiedType, UInt64}}
    packages::Vector{Base.PkgId}
end

mutable struct Inventory
    const file::InventoryFile
    config::InventoryConfig
    collections::Vector{CollectionInfo}
    stores::Vector{StoreSource}
    caches::Vector{CacheSource}
    last_gc::DateTime
end

≃(a::CollectionInfo, b::CollectionInfo) = a.uuid == b.uuid
≃(a::DataCollection, b::CollectionInfo) = a.uuid == b.uuid
≃(a::CollectionInfo, b::DataCollection) = b ≃ a

≃(a::SourceInfo, b::SourceInfo) = false
≃(a::StoreSource, b::StoreSource) =
    a.recipe == b.recipe && a.checksum === b.checksum &&
    a.extension == b.extension
≃(a::CacheSource, b::CacheSource) =
    a.recipe == b.recipe && a.types == b.types
