using Test
using Dates, UUIDs

using DataToolkitStore: DataToolkitStore, MonitoredFile, InventoryConfig,
    CollectionInfo, SourceInfo, Checksum, StoreSource, CacheSource, Inventory,
    LockFile, iscontested, checksum, MerkleTree, read_merkles, write_merkle,
    load_inventory, update_inventory!, modify_inventory!, save!,
    exclusively, flushpendingwrites, expunge!, update_source!,
    refresh_sources!, garbage_collect!

isdirty(inv::Inventory) = inv.batch.edits > inv.batch.written

using DataToolkitStore.DataToolkitCore: DataToolkitCore, DataCollection,
    DataStorage, DataLoader, dataset, loadcollection!

using DataToolkitStore.LockFiles: pidlive, pidqueue, overwrite

@testset "Checksums" begin
    @test checksum(:k12, "DataToolkitStore") ==
        Checksum(:k12, UInt8[0xec, 0xd8, 0x57, 0xba, 0x30, 0xf4, 0x70, 0x68, 0xa2, 0x45, 0x1f, 0x97, 0xa9, 0x22, 0x42, 0x01])
    @test checksum(:sha512, "DataToolkitStore") ==
        Checksum(:sha512, UInt8[0x67, 0x10, 0xd5, 0x9c, 0xfc, 0xf9, 0x89, 0x15, 0x74, 0x61, 0x1b, 0x97, 0xb4, 0x19, 0x8a, 0x8f, 0xa3, 0xb3, 0x0a, 0x5b, 0x5a, 0x81, 0x17, 0xb9, 0x9e, 0x61, 0xed, 0x92, 0x68, 0xe2, 0xb5, 0x4c, 0xaa, 0x12, 0xb1, 0x14, 0x22, 0x4b, 0x8f, 0x1e, 0x54, 0xe6, 0x98, 0x7b, 0x21, 0xe7, 0x1b, 0x28, 0xb7, 0x94, 0x20, 0x2e, 0x44, 0xcd, 0x78, 0xf0, 0x54, 0x60, 0x5f, 0x83, 0xac, 0x43, 0xae, 0x9f])
    @test checksum(:sha384, "DataToolkitStore") ==
        Checksum(:sha384, UInt8[0x81, 0xb6, 0x09, 0xfa, 0x56, 0xc5, 0x25, 0x5f, 0xb8, 0x75, 0xd0, 0xe9, 0x1d, 0x3d, 0x16, 0xb7, 0x94, 0xaa, 0x2f, 0xda, 0x16, 0xf9, 0x37, 0x06, 0x5f, 0x4d, 0x41, 0xbf, 0xd9, 0x21, 0x59, 0x5a, 0xfa, 0x2b, 0x9d, 0xec, 0xa1, 0x91, 0x05, 0x8a, 0xc0, 0x4e, 0x6d, 0x73, 0xc2, 0x52, 0xfd, 0x9b])
    @test checksum(:sha256, "DataToolkitStore") ==
        Checksum(:sha256, UInt8[0x7e, 0x73, 0x08, 0x35, 0xc1, 0x17, 0x0f, 0xa0, 0xa5, 0xfb, 0x7b, 0xf0, 0xd2, 0x26, 0xfa, 0x77, 0x4b, 0xd6, 0xe0, 0x11, 0x82, 0xcb, 0xca, 0xe8, 0x77, 0xc2, 0x54, 0xf8, 0x74, 0x30, 0x27, 0x68])
    @test checksum(:sha224, "DataToolkitStore") ==
        Checksum(:sha224, UInt8[0xb6, 0xd9, 0x3d, 0x0f, 0xae, 0xe0, 0x4f, 0x9e, 0x8f, 0x3e, 0x06, 0x22, 0x50, 0x7c, 0x00, 0x9b, 0x68, 0x9b, 0x84, 0xc2, 0x27, 0xf3, 0xd3, 0xee, 0xcd, 0xdf, 0x63, 0x9d])
    @test checksum(:sha1, "DataToolkitStore") ==
        Checksum(:sha1, UInt8[0x34, 0xc9, 0xf8, 0x3f, 0x10, 0x11, 0x77, 0xdc, 0x2e, 0x40, 0x9f, 0xaa, 0x88, 0xad, 0xa8, 0xb2, 0x38, 0x58, 0xe2, 0x7b])
    @test checksum(:md5, "DataToolkitStore") ==
        Checksum(:md5, UInt8[0x2c, 0xd6, 0x92, 0x26, 0xc8, 0xe9, 0x15, 0xe9, 0xda, 0xbb, 0x7f, 0xaa, 0xaa, 0x58, 0x7f, 0x6d])
    @test checksum(:crc32c, "DataToolkitStore") ==
        Checksum(:crc32c, UInt8[0xea, 0xbc, 0x8a, 0x08])
    # Uppercase hex parses to the same checksum as lowercase (else a
    # user-written "sha256:ABCD…" would silently disable verification).
    @test tryparse(Checksum, "sha256:ABCDEF") == tryparse(Checksum, "sha256:abcdef")
end

@testset "Lockfile" begin
    # Fabricated queue entries stand in for other processes: one PID that is
    # live (hopefully it outlasts the test) and one that is dead.
    livepid = Int32(1)
    while !pidlive(livepid)
        livepid += Int32(1)
    end
    deadpid = livepid + Int32(1)
    while pidlive(deadpid)
        deadpid += Int32(1)
    end
    lf = LockFile(joinpath(mktempdir(), "test.lock"))
    @test isfile(lf.path)
    @test !islocked(lf)
    # Claim and release
    @test trylock(lf)
    @test islocked(lf)
    @test pidqueue(lf) == Int32[lf.pid]
    @test !iscontested(lf)
    unlock(lf)
    @test !islocked(lf)
    @test isempty(pidqueue(lf))
    # A live foreign claimant blocks us, a dead one is pruned
    overwrite(lf, Int32[livepid, lf.pid]); truncate(lf.file, 2 * sizeof(Int32))
    @test !trylock(lf)
    @test islocked(lf)
    @test iscontested(lf)
    overwrite(lf, Int32[deadpid, lf.pid]); truncate(lf.file, 2 * sizeof(Int32))
    @test trylock(lf)
    @test pidqueue(lf) == Int32[lf.pid]
    @test !iscontested(lf)
    unlock(lf)
    # `lock` queues FIFO behind a live claimant, and wins once it revokes
    overwrite(lf, Int32[livepid]); truncate(lf.file, sizeof(Int32))
    locker = @async lock(lf)
    sleep(0.2)
    @test !istaskdone(locker)
    @test pidqueue(lf) == Int32[livepid, lf.pid]
    overwrite(lf, Int32[Int32(-1), lf.pid])
    @test timedwait(() -> istaskdone(locker), 5.0) === :ok
    @test pidqueue(lf) == Int32[lf.pid]
    unlock(lf)
end

@testset "Inventory writer" begin
    inv = update_inventory!(joinpath(mktempdir(), "Inventory.toml"))
    # A deferred edit opens a batch that flushes itself clean
    save!(inv)
    @test timedwait(() -> !isdirty(inv), 5.0) === :ok
    @test !inv.batch.locked && isnothing(inv.batch.writer)
    # A burst of edits batches into a single consistent flush
    inv.batch.writeduration = 0.3
    mt0 = mtime(inv.file.path)
    save!(inv); save!(inv); save!(inv)
    @test isdirty(inv) && inv.batch.locked && !isnothing(inv.batch.writer)
    @test timedwait(() -> !isdirty(inv), 10.0) === :ok
    @test timedwait(() -> isnothing(inv.batch.writer), 5.0) === :ok
    @test !inv.batch.locked && inv.batch.edits == inv.batch.written
    @test mtime(inv.file.path) > mt0
    # `exclusively` holds the file lock around `f` and passes the result through
    @test exclusively(i -> i.batch.locked, inv)
    @test !inv.batch.locked
    # `modify_inventory!` transactions are durable
    uuid = uuid4()
    modify_inventory!(inv) do i
        push!(i.collections, CollectionInfo(uuid, nothing, "test", now()))
    end
    @test occursin(string(uuid), read(inv.file.path, String))
    # With the batch writer parked on a pathological debounce, a synchronous
    # write clears dirtiness immediately, as does `flushpendingwrites`
    parked = update_inventory!(joinpath(mktempdir(), "Inventory.toml"))
    parked.batch.writeduration = 30.0
    save!(parked)
    @test isdirty(parked)
    write(parked)
    @test !isdirty(parked)
    save!(parked)
    @test isdirty(parked)
    flushpendingwrites()
    @test !isdirty(parked)
    # A failed flush drops the pending edits and resynchronises from disk
    fragiledir = mktempdir()
    fragile = update_inventory!(joinpath(fragiledir, "Inventory.toml"))
    kept = uuid4()
    modify_inventory!(i -> push!(i.collections, CollectionInfo(kept, nothing, "kept", now())), fragile)
    push!(fragile.collections, CollectionInfo(uuid4(), nothing, "dropped", now()))
    chmod(fragiledir, 0o500)
    @test_logs (:warn, r"^Failed to write the inventory") match_mode=:any begin
        save!(fragile)
        @test timedwait(() -> !isdirty(fragile), 5.0) === :ok
    end
    @test !fragile.batch.locked && isnothing(fragile.batch.writer)
    chmod(fragiledir, 0o700)
    @test getfield.(update_inventory!(fragile).collections, :uuid) == [kept]
end

@testset "Inventory transaction safety" begin
    # A stale instance (as from another process) must not clobber other writes
    path = joinpath(mktempdir(), "Inventory.toml")
    fresh, stale = load_inventory(path), load_inventory(path)
    doomed = CollectionInfo(uuid4(), nothing, "doomed", trunc(now(), Dates.Second))
    modify_inventory!(i -> push!(i.collections, doomed), stale)
    survivor = uuid4()
    modify_inventory!(i -> push!(i.collections, CollectionInfo(survivor, nothing, "survivor", now())), fresh)
    expunge!(stale, doomed)
    @test occursin(string(survivor), read(path, String))
    @test !occursin(string(doomed.uuid), read(path, String))
    # A failed lock acquisition leaves the batch clean
    fragile = load_inventory(joinpath(mktempdir(), "Inventory.toml"))
    close(fragile.batch.lock.file)
    rm(fragile.batch.lock.path)
    chmod(dirname(fragile.batch.lock.path), 0o500)
    @test_throws Exception save!(fragile)
    @test !isdirty(fragile)
    chmod(dirname(fragile.batch.lock.path), 0o700)
    # `flushpendingwrites` covers inventories obtained via `load_inventory`
    stray = load_inventory(joinpath(mktempdir(), "Inventory.toml"))
    stray.batch.writeduration = 30.0 # park the batch writer beyond the test horizon
    marker = uuid4()
    push!(stray.collections, CollectionInfo(marker, nothing, "stray", now()))
    save!(stray)
    @test isdirty(stray)
    flushpendingwrites()
    @test !isdirty(stray)
    @test occursin(string(marker), read(stray.file.path, String))
    # Unnormalised paths resolve to the registered inventory, not a duplicate
    dupdir = mktempdir()
    canonical = update_inventory!(joinpath(dupdir, "Inventory.toml"))
    zigzag = joinpath(dupdir, "..", basename(dupdir), "Inventory.toml")
    @test DataToolkitStore.getinventory(zigzag) === canonical
    # Recording a new store source is durable immediately, not debounced.
    durable = load_inventory(joinpath(mktempdir(), "Inventory.toml"))
    durable.batch.writeduration = 30.0
    collection = DataCollection("test")
    source = StoreSource(zero(UInt64), [collection.uuid], now(), nothing, "txt")
    update_source!(durable, source, collection)
    @test !isdirty(durable)
    @test occursin(string(collection.uuid), read(durable.file.path, String))
end

DataToolkitCore.getstorage(::DataStorage{:testblob}, ::Type{IO}) =
    IOBuffer(codeunits("hello blob"))

@testset "Store plugin integration" begin
    storedir = mktempdir()
    data_toml = joinpath(mktempdir(), "Data.toml")
    write(data_toml, """
    data_config_version = 0
    uuid = "$(uuid4())"
    name = "testcollection"
    plugins = ["store"]

    [config.store]
    path = "$storedir"

    [[blob]]
    uuid = "$(uuid4())"

        [[blob.storage]]
        driver = "testblob"
    """)
    loadcollection!(data_toml)
    inventory = DataToolkitStore.getinventory(dataset("blob").collection)
    # The first read caches the blob in the store, durably recorded
    @test read(open(dataset("blob"), IO), String) == "hello blob"
    @test length(inventory.stores) == 1
    @test occursin("[[store]]", read(inventory.file.path, String))
    # Later reads are served from the store
    cachefile = DataToolkitStore.storefile(inventory, only(dataset("blob").storage))
    @test !isnothing(cachefile) && isfile(cachefile)
    @test read(open(dataset("blob"), IO), String) == "hello blob"
    # Opening for writing removes the now-stale store entry
    @test open(dataset("blob"), IO; write = true) isa IO
    @test isempty(inventory.stores)
    @test !occursin("[[store]]", read(inventory.file.path, String))
end

@testset "Lifetime interpretation" begin
    interpret = DataToolkitStore.interpret_lifetime
    day = 24 * 60 * 60
    @test interpret("3 days") == 3day
    @test interpret("  3 days") == 3day
    @test interpret("4d12h") == 4day + 12 * 60 * 60
    @test interpret("1 week, 2 days") == 9day
    @test interpret("P23DT23H") == 23day + 23 * 60 * 60
    @test interpret("PT1H30M") == 90 * 60
    # A non-period prefix warns rather than hanging or mis-parsing
    @test (@test_logs (:warn, r"^Unmatched content") interpret("about 3 days")) == 3day
end

const COUNTER_CALLS = Ref(0)
DataToolkitCore.getstorage(::DataStorage{:nullsrc}, ::Type{IO}) = IOBuffer()
DataToolkitCore.load(::DataLoader{:counter}, ::Any, ::Type{Vector{Int}}) =
    (COUNTER_CALLS[] += 1; [COUNTER_CALLS[]])
DataToolkitCore.supportedtypes(::Type{DataLoader{:counter}}) =
    [DataToolkitCore.QualifiedType(Vector{Int})]

@testset "Cache plugin tolerates an unusable cache" begin
    storedir = mktempdir()
    data_toml = joinpath(mktempdir(), "Data.toml")
    write(data_toml, """
    data_config_version = 0
    uuid = "$(uuid4())"
    name = "cachetest"
    plugins = ["cache"]

    [config.store]
    path = "$storedir"

    [[nums]]
    uuid = "$(uuid4())"

        [[nums.storage]]
        driver = "nullsrc"

        [[nums.loader]]
        driver = "counter"
    """)
    loadcollection!(data_toml)
    COUNTER_CALLS[] = 0
    inventory = DataToolkitStore.getinventory(dataset("nums").collection)
    # First read runs the loader and caches the result.
    @test read(dataset("nums"), Vector{Int}) == [1]
    cachefile = DataToolkitStore.storefile(inventory, only(dataset("nums").loaders), Vector{Int})
    @test !isnothing(cachefile) && isfile(cachefile)
    # A corrupt cache file must not fail the read: it is discarded and the
    # loader re-run (COUNTER increments again) rather than deserialize throwing.
    chmod(cachefile, 0o644)
    write(cachefile, "not a valid serialization")
    result = @test_logs (:warn,) match_mode=:any read(dataset("nums"), Vector{Int})
    @test result == [2]
end

@testset "GC dry run is non-destructive" begin
    inv = load_inventory(joinpath(mktempdir(), "Inventory.toml"))
    refs = [uuid4(), uuid4()]
    push!(inv.stores, StoreSource(zero(UInt64), copy(refs), now(), nothing, "txt"))
    # No active/inactive collections, so every reference would be dropped and
    # the source orphaned — but a dry run must leave it untouched.
    (; orphan_sources) = refresh_sources!(inv; active_collections = Dict{UUID, Set{UInt64}}(),
                                          inactive_collections = Set{UUID}(), dryrun = true)
    @test length(orphan_sources) == 1
    @test length(inv.stores) == 1
    @test inv.stores[1].references == refs
    # A dry-run expunge reports a source it would orphan (its sole reference)
    # without mutating it.
    solo = uuid4()
    push!(inv.stores, StoreSource(one(UInt64), [solo], now(), nothing, "txt"))
    coll = CollectionInfo(solo, nothing, "c", now())
    removed = expunge!(inv, coll; dryrun = true)
    @test length(removed) == 1
    @test inv.stores[end].references == [solo]
    # A collection sharing a source with another is not reported as orphaning it.
    @test isempty(expunge!(inv, CollectionInfo(refs[1], nothing, "c", now()); dryrun = true))
end

@testset "GC removes orphan files and keeps the inventory" begin
    dir = mktempdir()
    inv = load_inventory(joinpath(dir, "Inventory.toml"))
    storedir = joinpath(dir, inv.config.store_dir); mkpath(storedir)
    orphan = joinpath(storedir, "unreferenced.cache")
    write(orphan, "no source points here")
    # A real GC (report to devnull) deletes the orphan but leaves the inventory.
    redirect_stdout(devnull) do
        garbage_collect!(inv)
    end
    @test !isfile(orphan)
    @test isfile(inv.file.path)
end

@testset "Merkle trees" begin
    serialised_sample_mtree = """
    d 101t3scp5ey9w alg:1234 some/dir
      f 101t3scouw0l3 alg:2345 file
      f 101t3scoizz9p alg:4567 other
      d 101t3sco1ppsw alg:5678 subdir
        f 101t3scmmw8mh alg:6789 file
        f 101t3scmjk9mt alg:7890 other
      d 101t3t7a8rqzc alg:8901 another
        d 101t3t8udhoyc alg:9012 nested
          f 101t3t7atpdsv alg:0123 lone
    """
    sample_mtree = MerkleTree("some/dir", 1.718190355243043e9, Checksum(:alg, UInt8[0x12, 0x34]), MerkleTree[
        MerkleTree("file", 1.718190351027891e9, Checksum(:alg, UInt8[0x23, 0x45]), nothing),
        MerkleTree("other", 1.718190346266559e9, Checksum(:alg, UInt8[0x45, 0x67]), nothing),
        MerkleTree("subdir", 1.718190339344719e9, Checksum(:alg, UInt8[0x56, 0x78]), MerkleTree[
            MerkleTree("file", 1.718190318994242e9, Checksum(:alg, UInt8[0x67, 0x89]), nothing),
            MerkleTree("other", 1.718190317659715e9, Checksum(:alg, UInt8[0x78, 0x90]), nothing)]),
        MerkleTree("another", 1.718206228888754e9, Checksum(:alg, UInt8[0x89, 0x01]), MerkleTree[
            MerkleTree("nested", 1.718207038089696e9, Checksum(:alg, UInt8[0x90, 0x12]), MerkleTree[
                MerkleTree("lone", 1.718206237271919e9, Checksum(:alg, UInt8[0x01, 0x23]), nothing)])])])
    @test sprint(write_merkle, sample_mtree) == serialised_sample_mtree
    parsed = read_merkles(IOBuffer(serialised_sample_mtree))
    @test length(parsed) == 1
    @test sprint(write_merkle, only(parsed)) == serialised_sample_mtree
    # Directory checksums are location-independent, so they survive relocation
    # and hold across machines
    function filltree(dir)
        write(joinpath(dir, "file"), "hello")
        mkdir(joinpath(dir, "sub"))
        write(joinpath(dir, "sub", "nested"), "world")
        mkdir(joinpath(dir, "emptydir"))
        dir
    end
    twin1, twin2 = filltree(mktempdir()), filltree(mktempdir())
    @test DataToolkitStore.merkle("", twin1, :crc32c).checksum ==
        DataToolkitStore.merkle("", twin2, :crc32c).checksum
    # A throw from the hashing function must degrade gracefully: no exception
    # escapes a worker, the pool counter never strands (so the build terminates
    # rather than spinning), and failed entries fold in as a reserved
    # inaccessible checksum rather than vanishing.
    tree = filltree(mktempdir())
    exploding(_io) = error("boom")
    result = Threads.@spawn DataToolkitStore.merkle("", tree, exploding)
    @test timedwait(() -> istaskdone(result), 20.0) === :ok
    built = fetch(result)
    @test built isa MerkleTree
    @test all(c -> c.checksum == DataToolkitStore.MERKLE_INACCESSIBLE, built.children)
end
