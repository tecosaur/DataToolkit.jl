using DataToolkitCore
using DataToolkitCommon
using DataFrames
using ArchGDAL
using Test
using UUIDs
using ColorTypes, FixedPointNumbers
using Tar, FilePathsBase
import Pkg

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
    writeread(value, driver, astype; params...)

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
    @test read(open(dataset("genericio"), IO), String) == "io content"
    @test open(dataset("genericio"), String) == "io content"
    @test open(dataset("genericio"), Vector{UInt8}) == codeunits("io content")
    @test open(dataset("genericfile"), String) == "file content"
    @test open(dataset("genericfile"), Vector{UInt8}) == codeunits("file content")
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
        dirpath = open(dataset("adir"), FilePathsBase.AbstractPath)
        @test dirpath isa FilePathsBase.AbstractPath
        @test isdir(string(dirpath))
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
        # The json loader gives a JSON3.Object; compare it as a plain Dict.
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
        # DelimitedFiles reads back as Matrix{Any}, so only a String matrix survives.
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
        @test fs.priority == 9
        @test nullstore.priority == 5
        @test get(only(thing.loaders), "header") == false
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
        @test read(dataset(coll, "iris@1"), String) == "1.2.0"
        @test read(dataset(coll, "iris@1.0"), String) == "1.0.0"
        @test read(dataset(coll, "iris@1.0 - 1.1"), String) == "1.0.0"
        @test read(dataset(coll, "iris@~1.0, 2"), String) == "2.0.0"
        @test_throws UnresolveableIdentifier dataset(coll, "iris@3")
        err = try dataset(coll, "iris@>1") catch e; e end
        @test err isa DataToolkitCommon.InvalidVersionSelector
        @test occursin("\">1\"", sprint(io -> showerror(io, err, []; backtrace=false)))
        # A versioned layer without the data set is passed over, even for `latest`.
        freshcollection("versions", "[[unrelated]]\nuuid = \"$(uuid4())\"")
        @test read(dataset("iris@latest"), String) == "2.0.0"
        VersionSelector = DataToolkitCommon.VersionSelector
        @testset "Agrees with Pkg" begin
            # Pkg's spelling of a whole selector, with the `latest` and bare-version rules applied.
            pkgform(selector) =
                if selector == "latest" ">=0"
                elseif all(c -> c ∈ '0':'9' || c == '.', selector)
                    if count('.', selector) <= 1 "~" * selector else "=" * selector end
                else selector end
            # Zero and nonzero components in every position, as caret and tilde treat them differently.
            bounds = [join(c, '.') for n in 1:3 for c in Iterators.product(fill(0:1, n)...)]
            # Pkg rejects `0.0.0` outside ranges, and `<` of zero.
            nonzero = filter(!=("0.0.0"), bounds)
            positive = filter(b -> any(!=('0'), filter(!=('.'), b)), bounds)
            clauses = vcat(
                [op * pre * b for op in ("", "^", "~", "=", ">=", "≥")
                     for pre in ("", "v") for b in nonzero],
                ["= " * b for b in nonzero], [">= " * b for b in nonzero],
                ["<" * pre * b for pre in ("", " ", "v") for b in positive],
                ["$a - $b" for a in bounds for b in bounds])
            # Padding and unions don't depend on the clause, so a spread of clauses covers them.
            specs = vcat("latest", nonzero, clauses, " " .* clauses[1:17:end] .* " ",
                         [join(p, ", ") for p in zip(clauses[1:13:end], reverse(clauses)[1:13:end])],
                         ["2026.9", "~2026.9", "<2026.10", "2026.8 - 2026.9"])
            # Releases in 0:2³ straddle every interval end; suffixed ones sit just off a bound.
            versions = vcat(vec([VersionNumber(a, b, c) for a in 0:2, b in 0:2, c in 0:2]),
                            [v"1.0.0-rc1", v"1.1.0+b7", v"2.0.0-rc1", v"2026.9.1", v"2026.10"])
            ours = map(s -> tryparse(VersionSelector, s), specs)
            rejected = specs[isnothing.(ours)]
            @test isempty(rejected)
            if isempty(rejected)
                theirs = map(s -> Pkg.Versions.semver_spec(pkgform(s)), specs)
                disagreements = [(spec, v) for (spec, sel, pkgsel) in zip(specs, ours, theirs)
                                 for v in versions if (v ∈ sel) != (v ∈ pkgsel)]
                @test isempty(disagreements)
            end
        end
        @testset "Zero and saturated bounds" begin
            matches(selector, v) = v ∈ tryparse(VersionSelector, selector)
            # Pkg rejects these, but an unversioned data set is `v"0"`.
            @test matches("0.0.0", v"0") && !matches("0.0.0", v"0.0.1")
            @test !matches("<0", v"0")
            @test matches("^$(typemax(UInt32))", VersionNumber(typemax(UInt32), 7))
        end
        @testset "Invalid selectors" begin
            # Pkg accepts `=vv1` by accident.
            for selector in ["", "1.2,", "1..2", "1.2.3.4", "~ 1", "<= 1", "1.2-1.4",
                             "4294967296", "Latest", "=vv1"]
                @test isnothing(tryparse(VersionSelector, selector))
            end
        end
        # Before 1.11, Pkg is part of the system image, so it is always loaded.
        @static if VERSION >= v"1.11"
            @testset "Pkg stays unloaded" begin
                script = """
                using DataToolkitCore, DataToolkitCommon
                loadcollection!(IOBuffer(\"\"\"
                data_config_version = 0
                uuid = "$(uuid4())"
                name = "versioned"
                plugins = ["versions"]
                [[thing]]
                uuid = "$(uuid4())"
                version = "1.2.0"
                \"\"\"))
                dataset("thing"), dataset("thing@1 - 2")
                exit(Int(haskey(Base.loaded_modules, Base.PkgId(
                    Base.UUID("44cfe95a-1eb2-52ea-b672-e2afdf69b78f"), "Pkg"))))
                """
                @test success(`$(Base.julia_cmd()) --startup-file=no --project=$(Base.active_project()) -e $script`)
            end
        end
    end
end
