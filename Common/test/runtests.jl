using DataToolkitCore
using DataToolkitCommon
using DataFrames
using ArchGDAL
using Test
using UUIDs
using ColorTypes, FixedPointNumbers
using Tar, FilePathsBase

DataToolkitCore.loadcollection!("Data.toml")

"""
    writeread(value, driver, astype; readtype=QualifiedType(astype), params...)

Round-trip `value` through a fresh filesystem-backed dataset: write it with the
`driver` writer, read it back as `astype` with the matching loader, exercising
the real `write`/`read` path (format writer + file storage). `params` become
writer arguments. Returns the value read back so the caller can assert on it.
"""
function writeread(value, driver::String, astype::Type; params...)
    dir = mktempdir()
    file = joinpath(dir, "data.$driver")
    valtype = string(QualifiedType(typeof(value)))
    astypestr = string(QualifiedType(astype))
    writerparams = join(("\n        args.$k = $(sprint(show, v))" for (k, v) in params))
    write(joinpath(dir, "Data.toml"), """
    data_config_version = 0
    uuid = "$(uuid4())"
    name = "rt-$(basename(dir))"

    [[item]]
    uuid = "$(uuid4())"

        [[item.storage]]
        driver = "filesystem"
        path = "$(basename(file))"
        type = ["FilePath", "IO"]
        priority = 1

        [[item.loader]]
        driver = "$driver"
        type = "$astypestr"

        [[item.writer]]
        driver = "$driver"
        type = "$valtype"$writerparams
    """)
    ds = only(loadcollection!(joinpath(dir, "Data.toml")).datasets)
    write(ds, value)
    read(ds, astype)
end

DataToolkitCore.getstorage(::DataStorage{:iobased}, ::Type{IO}) =
    IOBuffer(codeunits("io content"))

@testset "Generic storage fallbacks" begin
    gdir = mktempdir()
    write(joinpath(gdir, "content.txt"), "file content")
    write(joinpath(gdir, "Data.toml"), """
    data_config_version = 0
    uuid = "$(uuid4())"
    name = "genericstorage"

    [[genericfile]]
    uuid = "$(uuid4())"

        [[genericfile.storage]]
        driver = "filesystem"
        path = "content.txt"

    [[genericio]]
    uuid = "$(uuid4())"

        [[genericio.storage]]
        driver = "iobased"
    """)
    loadcollection!(joinpath(gdir, "Data.toml"))
    # Every form is derivable from a driver providing only one of them
    @test read(open(dataset("genericio"), IO), String) == "io content"
    @test open(dataset("genericio"), String) == "io content"
    @test open(dataset("genericio"), Vector{UInt8}) == codeunits("io content")
    @test open(dataset("genericfile"), String) == "file content"
    @test open(dataset("genericfile"), Vector{UInt8}) == codeunits("file content")
    # A missing file is absence (`nothing`), not a StackOverflowError
    rm(joinpath(gdir, "content.txt"))
    @test isnothing(open(dataset("genericfile"), IO))
    @test isnothing(open(dataset("genericfile"), String))
end

@testset "Write round-trips" begin
    @testset "csv" begin
        df = DataFrame(a = [1, 2, 3], b = ["x", "y", "z"])
        @test writeread(df, "csv", DataFrame) == df
    end
    @testset "png strategy/filter options" begin
        img = rand(RGB{N0f8}, 8, 8)
        for strat in ("default", "filtered", "huffman", "rle", "fixed"),
            filt in ("none", "sub", "up", "average", "paeth")
            back = writeread(img, "png", Matrix;
                             compression_strategy = strat, filters = filt)
            @test size(back) == size(img)
        end
    end
    @testset "compression writers" begin
        bytes = Vector{UInt8}("compress me, please\n"^100)
        text = "stream me\n"^50
        for driver in ("gzip", "zlib", "deflate", "bzip2", "xz", "zstd")
            @test writeread(bytes, driver, Vector{UInt8}) == bytes
            # A non-IOStream IO source (IOBuffer) must also round-trip.
            @test writeread(IOBuffer(text), driver, String) == text
        end
    end
    @testset "shorter rewrite truncates" begin
        dir = mktempdir()
        write(joinpath(dir, "Data.toml"), """
        data_config_version = 0
        uuid = "$(uuid4())"
        name = "rewrite"

        [[item]]
        uuid = "$(uuid4())"

            [[item.storage]]
            driver = "filesystem"
            path = "data.gzip"
            type = ["FilePath", "IO"]

            [[item.loader]]
            driver = "gzip"

            [[item.writer]]
            driver = "gzip"
            type = "Vector{UInt8}"
        """)
        ds = only(loadcollection!(joinpath(dir, "Data.toml")).datasets)
        write(ds, Vector{UInt8}("A"^5000))
        write(ds, Vector{UInt8}("B"^10))
        # No stale tail from the longer write may survive the shorter one.
        @test read(ds, Vector{UInt8}) == Vector{UInt8}("B"^10)
    end
    @testset "tar single file to IO" begin
        tdir = mktempdir(); mkdir(joinpath(tdir, "src"))
        write(joinpath(tdir, "src", "hello.txt"), "tar contents\n")
        dir = mktempdir()
        Tar.create(joinpath(tdir, "src"), joinpath(dir, "data.tar"))
        write(joinpath(dir, "Data.toml"), """
        data_config_version = 0
        uuid = "$(uuid4())"
        name = "tar"

        [[item]]
        uuid = "$(uuid4())"

            [[item.storage]]
            driver = "filesystem"
            path = "data.tar"

            [[item.loader]]
            driver = "tar"
            file = "hello.txt"
            type = "IO"
        """)
        ds = only(loadcollection!(joinpath(dir, "Data.toml")).datasets)
        # A direct IO consumer must see the bytes, not an exhausted stream.
        @test read(read(ds, IO), String) == "tar contents\n"
    end
    @testset "FilePathsBase paths" begin
        dir = mktempdir()
        write(joinpath(dir, "content.txt"), "path me\n")
        mkdir(joinpath(dir, "adir"))
        write(joinpath(dir, "Data.toml"), """
        data_config_version = 0
        uuid = "$(uuid4())"
        name = "paths"

        [[afile]]
        uuid = "$(uuid4())"

            [[afile.storage]]
            driver = "filesystem"
            path = "content.txt"
            type = ["FilePath", "AbstractPath"]

        [[adir]]
        uuid = "$(uuid4())"

            [[adir.storage]]
            driver = "filesystem"
            path = "adir"
            type = ["DirPath", "AbstractPath"]
        """)
        loadcollection!(joinpath(dir, "Data.toml"))
        filepath = open(dataset("afile"), FilePathsBase.AbstractPath)
        @test filepath isa FilePathsBase.AbstractPath
        @test read(string(filepath), String) == "path me\n"
        # Directory-backed storage surfaces as an AbstractPath too.
        dirpath = open(dataset("adir"), FilePathsBase.AbstractPath)
        @test dirpath isa FilePathsBase.AbstractPath
        @test isdir(string(dirpath))
    end
end

@testset "Storage" begin
    @testset "AWS S3" begin
        @test open(dataset("iris-s3"), FilePath) isa FilePath
    end
end

@testset "Loaders/Writers" begin
    @testset "arrow" begin
        @test size(read(dataset("iris-arrow"))) == (150, 5)
    end
    @testset "compression" begin
        iris = read(dataset("iris"), Matrix)
        @test read(dataset("iris-bzip2"), Matrix) == iris
        @test read(dataset("iris-gz"), Matrix) == iris
        @test read(dataset("iris-xz"), Matrix) == iris
        @test read(dataset("iris-zstd"), Matrix) == iris
    end
    @testset "csv" begin
        @test size(read(dataset("iris"), DataFrame)) == (150, 5)
    end
    # @testset "gif" begin # FIXME incompatible `ImageCore` compat with `WebP`
    #     @test read(dataset("lighthouse-gif"), Matrix) isa Matrix
    # end
    @testset "gpkg" begin
        geo = read(dataset("eurostat-gpkg"))
        @test geo isa ArchGDAL.IDataset
        @test ArchGDAL.getlayer(geo, 0) |> length == 1025
    end
    @testset "jpeg" begin
        @test read(dataset("lighthouse-jpeg"), Matrix) isa Matrix
    end
    @testset "jld2" begin
        @test size(read(dataset("iris-jld2"))) == (150, 5)
    end
    @testset "netpbm" begin
        # Currently broken, see <https://github.com/JuliaIO/Netpbm.jl/issues/39>
        # @test read(dataset("lighthouse-netpbm"), Matrix) isa Matrix
    end
    @testset "png" begin
        @test read(dataset("lighthouse-png"), Matrix) isa Matrix
    end
    @testset "qoi" begin
        @test read(dataset("lighthouse-qoi"), Matrix) isa Matrix
    end
    @testset "tar" begin
        @test sum(Vector{UInt8}(read(dataset("iris-tar"), String))) == 258587
    end
    @testset "tiff" begin
        @test read(dataset("lighthouse-tiff"), AbstractMatrix) isa AbstractMatrix
    end
    @testset "toml" begin
        @test sort([k => length(v) for (k, v) in read(dataset("sample-toml"))], by=first) ==
            ["database" => 4, "owner" => 2, "servers" => 2, "title" => 12]
    end
    @testset "webp" begin
        @test read(dataset("lighthouse-webp"), Matrix) isa Matrix
    end
    @testset "yaml" begin
        @test sort([k => length(v) for (k, v) in read(dataset("sample-yaml"))], by=first) ==
            ["database" => 4, "owner" => 2, "servers" => 2, "title" => 12]
    end
    @testset "zip" begin
        @test sum(read(read(dataset("iris-zip"), IO))) == 258587
    end
end
@testset "Plugins" begin
    @testset "Cache" begin
    end
    @testset "Defaults" begin
    end
    @testset "Log" begin
    end
    @testset "Memorise" begin
    end
    @testset "Store" begin
        @testset "Checksums" begin
            val = "Aren't checksums neat?\n"
            @test read(dataset("checksum-k12"),    String) == val
            @test read(dataset("checksum-crc32c"), String) == val
            @test read(dataset("checksum-md5"),    String) == val
            @test read(dataset("checksum-sha1"),   String) == val
            @test read(dataset("checksum-sha224"), String) == val
            @test read(dataset("checksum-sha256"), String) == val
            @test read(dataset("checksum-sha384"), String) == val
            @test read(dataset("checksum-sha512"), String) == val
        end
    end
    @testset "Versions" begin
    end
end
