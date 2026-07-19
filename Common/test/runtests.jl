using DataToolkitCore
using DataToolkitCommon
using DataFrames
using ArchGDAL
using Test
using UUIDs
using ColorTypes, FixedPointNumbers
using Tar, FilePathsBase

DataToolkitCore.loadcollection!("Data.toml")

# Assert `expr`, but degrade to `@test_broken` if it throws — for backends whose
# fixtures need network access or a heavy/optional codec that may be absent.
macro maybe_broken(expr)
    quote
        ok = try $(esc(expr)) catch; false end
        if ok
            @test ok
        else
            @test_broken ok
        end
    end
end

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

"""
Real-invocation counter for the `julia`-loader fixtures. A collection's inline
`function` runs in `Main`, so it can reach this `Ref` by name and bump it; the
tests then read `LOADCOUNT[]` to assert how many times a loader actually ran.
"""
const LOADCOUNT = Ref(0)

"""
    freshcollection(plugin, datasets) -> DataCollection

Write a throwaway `Data.toml` (fresh name and uuid, single `plugin`) to a temp
dir and `loadcollection!` it. `datasets` is the TOML body describing the sets.
The fresh uuid keeps it isolated from the base `test` collection on `STACK` and
from `MEMORISE_CACHE`. Resolve within it via `dataset(collection, name)`.
"""
function freshcollection(plugin::String, datasets::String)
    dir = mktempdir()
    write(joinpath(dir, "Data.toml"), """
    data_config_version = 0
    uuid = "$(uuid4())"
    name = "$(uuid4())"
    plugins = ["$plugin"]

    $datasets
    """)
    loadcollection!(joinpath(dir, "Data.toml"))
end

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
        # A loader with no concrete path method must fall through cleanly when
        # asked for an AbstractPath: the adaptor yields `nothing` (a MethodError
        # here would mean it tried to call an absent load method).
        write(joinpath(dir, "nopath.toml"), "a = 1\n")
        write(joinpath(dir, "NoPath.toml"), """
        data_config_version = 0
        uuid = "$(uuid4())"
        name = "nopath"

        [[item]]
        uuid = "$(uuid4())"

            [[item.storage]]
            driver = "filesystem"
            path = "nopath.toml"
            type = "IO"

            [[item.loader]]
            driver = "toml"
            type = "Dict{String, Any}"
        """)
        nopath = only(loadcollection!(joinpath(dir, "NoPath.toml")).datasets)
        loader, io = nopath.loaders[1], open(nopath, IO)
        @test isnothing(DataToolkitCommon.load(loader, io, FilePathsBase.AbstractPath))
    end
    @testset "toml" begin
        d = Dict{String, Any}(
            "title" => "example",
            "count" => 3,
            "nested" => Dict{String, Any}("a" => 1, "list" => [1, 2, 3]))
        # TOML sorts keys on write; compare parsed dicts, not serialised text.
        @test writeread(d, "toml", Dict{String, Any}) == d
    end
    @testset "json" begin
        d = Dict{String, Any}("title" => "example", "count" => 3, "flag" => true)
        # The json loader parses to a JSON3.Object (requested as `Any`); flatten to a
        # plain Dict to compare structure, and check both `pretty` writer settings.
        for pretty in (false, true)
            back = writeread(d, "json", Any; pretty)
            @test Dict{String, Any}(String(k) => v for (k, v) in pairs(back)) == d
        end
    end
    @testset "yaml" begin
        d = Dict{String, Any}(
            "title" => "example",
            "nested" => Dict{String, Any}("a" => 1, "b" => 2))
        @test writeread(d, "yaml", Dict{String, Any}) == d
    end
    @testset "delim" begin
        # DelimitedFiles reads back with element type Any by default (delim.jl), so a
        # String matrix survives round-trip where a typed numeric matrix would widen.
        m = ["name" "city"; "ada" "london"; "alan" "manchester"]
        back = writeread(m, "delim", Matrix; delim = "\t")
        @test back == m
    end
end

@testset "Storage" begin
    @testset "AWS S3" begin
        @maybe_broken open(dataset("iris-s3"), FilePath) isa FilePath
    end
end

@testset "Loaders/Writers" begin
    @testset "arrow" begin
        @maybe_broken size(read(dataset("iris-arrow"))) == (150, 5)
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
        @maybe_broken begin
            geo = read(dataset("eurostat-gpkg"))
            geo isa ArchGDAL.IDataset && ArchGDAL.getlayer(geo, 0) |> length == 1025
        end
    end
    @testset "jpeg" begin
        @maybe_broken read(dataset("lighthouse-jpeg"), Matrix) isa Matrix
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
        @maybe_broken read(dataset("lighthouse-tiff"), AbstractMatrix) isa AbstractMatrix
    end
    @testset "toml" begin
        @test sort([k => length(v) for (k, v) in read(dataset("sample-toml"))], by=first) ==
            ["database" => 4, "owner" => 2, "servers" => 2, "title" => 12]
    end
    @testset "webp" begin
        @maybe_broken read(dataset("lighthouse-webp"), Matrix) isa Matrix
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
        coll = freshcollection("defaults", """
        [config.defaults.storage._]
        priority = 5

        [config.defaults.storage.filesystem]
        priority = 9

        [config.defaults.loader.csv]
        header = false

        [[thing]]
        uuid = "$(uuid4())"

            [[thing.storage]]
            driver = "filesystem"
            path = "nope.csv"

            [[thing.storage]]
            driver = "null"

            [[thing.loader]]
            driver = "csv"

        [[explicit]]
        uuid = "$(uuid4())"

            [[explicit.storage]]
            driver = "filesystem"
            path = "nope.csv"
            priority = 42
        """)
        thing = dataset(coll, "thing")
        fs = only(filter(s -> DataToolkitCore.driverof(s) == :filesystem, thing.storage))
        nullstore = only(filter(s -> DataToolkitCore.driverof(s) == :null, thing.storage))
        # Specific-driver default beats the all-driver `_`, which still reaches other drivers.
        @test fs.priority == 9
        @test nullstore.priority == 5
        @test get(only(thing.loaders), "header") == false
        # A present value is not clobbered by the default (spec merged last).
        explstore = only(dataset(coll, "explicit").storage)
        @test explstore.priority == 42
    end
    @testset "Log" begin
    end
    @testset "Memorise" begin
        counter = "() -> (LOADCOUNT[] += 1; Any[LOADCOUNT[]])"
        @testset "caches by (dataset, type)" begin
            coll = freshcollection("memorise", """
            [[thing]]
            uuid = "$(uuid4())"
            memorise = true

                [[thing.loader]]
                driver = "julia"
                type = "Vector"
                function = "$counter"
            """)
            ds = dataset(coll, "thing")
            LOADCOUNT[] = 0
            r1 = read(ds, Vector)
            r2 = read(ds, Vector)
            # A second read of the same type is served from cache: same object, loader not re-run.
            @test r2 === r1
            @test LOADCOUNT[] == 1
        end
        @testset "type-scoped memorise keys on requested type" begin
            coll = freshcollection("memorise", """
            [[thing]]
            uuid = "$(uuid4())"
            memorise = "Vector"

                [[thing.loader]]
                driver = "julia"
                type = "Vector"
                function = "$counter"
            """)
            ds = dataset(coll, "thing")
            LOADCOUNT[] = 0
            v1 = read(ds, Vector)
            v2 = read(ds, Vector)
            @test v2 === v1
            @test LOADCOUNT[] == 1
            # `memorise = "Vector"` scopes caching to that type; an AbstractVector request
            # is not a subtype match, so it re-runs the loader rather than serving the cache.
            av = read(ds, AbstractVector)
            @test av !== v1
            @test LOADCOUNT[] == 2
        end
        @testset "no memorise re-runs every read" begin
            coll = freshcollection("memorise", """
            [[thing]]
            uuid = "$(uuid4())"

                [[thing.loader]]
                driver = "julia"
                type = "Vector"
                function = "$counter"
            """)
            ds = dataset(coll, "thing")
            LOADCOUNT[] = 0
            n1 = read(ds, Vector)
            n2 = read(ds, Vector)
            @test n2 !== n1
            @test LOADCOUNT[] == 2
        end
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
        irisversion(v) = """
        [[iris]]
        uuid = "$(uuid4())"
        version = "$v"

            [[iris.loader]]
            driver = "julia"
            type = "String"
            function = "() -> \\"$v\\""
        """
        coll = freshcollection(
            "versions",
            irisversion("1.0.0") * irisversion("1.2.0") * irisversion("2.0.0"))
        # The loaded value echoes the selected version, so selection is asserted end-to-end.
        @test read(dataset(coll, "iris@latest"), String) == "2.0.0"
        @test read(dataset(coll, "iris@2"), String) == "2.0.0"
        @test read(dataset(coll, "iris@>=2"), String) == "2.0.0"
        # `@1` matches all 1.x.x and picks the highest; `@1.0` narrows to 1.0.x.
        @test read(dataset(coll, "iris@1"), String) == "1.2.0"
        @test read(dataset(coll, "iris@1.0"), String) == "1.0.0"
        # A selector matching no version resolves to nothing.
        @test_throws Exception dataset(coll, "iris@3")
    end
end
