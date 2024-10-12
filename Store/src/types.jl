mutable struct MonitoredFile
    const path::String
    mtime::Float64
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

struct Checksum
    alg::Symbol
    hash::Vector{UInt8} # REVIEW Use static Memory{UInt8} when possible
end

struct StoreSource <: SourceInfo
    recipe::UInt64
    references::Vector{UUID}
    accessed::DateTime
    checksum::Union{Nothing, Checksum}
    extension::String
end

struct CacheSource <: SourceInfo
    recipe::UInt64
    references::Vector{UUID}
    accessed::DateTime
    types::Vector{Pair{QualifiedType, UInt64}}
    packages::Vector{Base.PkgId}
end

struct MerkleTree
    path::String
    mtime::Float64
    checksum::Checksum
    children::Union{Nothing, Vector{MerkleTree}}
end

struct CachedMerkles
    file::MonitoredFile
    merkles::Vector{MerkleTree}
end

mutable struct Inventory
    const file::MonitoredFile
    const lock::LockFile
    const merkles::CachedMerkles
    config::InventoryConfig
    collections::Vector{CollectionInfo}
    stores::Vector{StoreSource}
    caches::Vector{CacheSource}
    last_gc::DateTime
end

Base.:(==)(a::Checksum, b::Checksum) =
    a.alg == b.alg && a.hash == b.hash

Base.hash(c::Checksum, h::UInt) =
    hash(c.alg, hash(c.hash, h))

≃(a::CollectionInfo, b::CollectionInfo) = a.uuid == b.uuid
≃(a::DataCollection, b::CollectionInfo) = a.uuid == b.uuid
≃(a::CollectionInfo, b::DataCollection) = b ≃ a

≃(a::SourceInfo, b::SourceInfo) = false
≃(a::StoreSource, b::StoreSource) =
    a.recipe == b.recipe && a.checksum == b.checksum &&
    a.extension == b.extension
≃(a::CacheSource, b::CacheSource) =
    a.recipe == b.recipe && a.types == b.types

function MonitoredFile(path)
    recency = if isfile(path) mtime(path) else time() end
    writable = !isfile(path) || try
        open(io -> iswritable(io), path, "a")
    catch e
        if e isa SystemError
            false
        else
            rethrow()
        end
    end
    MonitoredFile(abspath(path), recency, writable)
end
