using Test

using DataToolkitStore: DataToolkitStore, MonitoredFile, InventoryConfig,
    CollectionInfo, SourceInfo, Checksum, StoreSource, CacheSource, Inventory,
    LockFile, iscontested, checksum

using DataToolkitStore.LockFiles: pidlive, pidqueue, LOCKFILE_OPEN_FLAGS, LOCKFILE_OPEN_MODE

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
end

@testset "Lockfile" begin
    # Get any two other live PIDs so we can pretend to
    # be multiple processes trying to lock the same file.
    # Hopefully they won't die while this test is running...
    fauxpid1, fauxpid2 = Int32(1), Int32(0)
    while !pidlive(fauxpid1)
        fauxpid1 += 0x1
    end
    fauxpid2 = fauxpid1 + 0x1
    while pidlive(fauxpid2)
        fauxpid2 += 0x1
    end
    lf1 = LockFile(DataToolkitStore.PROJECT_SUBPATH, "test", "a")
    lf2 = LockFile(ReentrantLock(), lf1.path,
                   Base.Filesystem.open(lf1.path, LOCKFILE_OPEN_FLAGS, LOCKFILE_OPEN_MODE),
                   fauxpid1, false, false, 0.0)
    lf3 = LockFile(ReentrantLock(), lf1.path,
                   Base.Filesystem.open(lf1.path, LOCKFILE_OPEN_FLAGS, LOCKFILE_OPEN_MODE),
                   fauxpid2, false, false, 0.0)
    @test isfile(lf1.path)
    @test !islocked(lf1)
    @test !islocked(lf2)
    # Acquire the lock on lf1
    @test trylock(lf1)
    @test islocked(lf1)
    @test !iscontested(lf1)
    @test length(pidqueue(lf1)) == 1
    @test first(pidqueue(lf1)) == lf1.pid
    @test islocked(lf2)
    # Check that lf1 can be re-entrantly locked
    @test trylock(lf1)
    @test islocked(lf1)
    unlock(lf1)
    @test islocked(lf1)
    # Confirm that lf2 can't grab the lock
    @test !trylock(lf2)
    # Now unlock lf1 and try again with lf2
    unlock(lf1)
    @test length(pidqueue(lf1)) == 0
    @test trylock(lf2)
    # Create two tasks trying to aquire lf2
    @test !iscontested(lf2)
    lt1 = @async lock(lf1)
    lt3 = @async lock(lf3)
    sleep(0.01)
    @test iscontested(lf2)
    @test !istaskdone(lt1)
    @test !istaskdone(lt3)
    @test first(pidqueue(lf2)) == lf2.pid
    @test length(pidqueue(lf2)) == 3
    _, q2, q3 = pidqueue(lf2)
    @test q2 ∈ (lf1.pid, lf3.pid)
    @test q3 ∈ (lf1.pid, lf3.pid)
    @test q2 != q3
    unlock(lf2)
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
end
