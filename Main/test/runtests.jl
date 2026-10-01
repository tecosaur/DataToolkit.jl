# Keep the auto-init walk of the ambient load path from mutating the shared
# global STACK before the suite starts. Must be set before `using DataToolkit`.
ENV["DATA_TOOLKIT_AUTO_INIT"] = "no"
# Likewise, so the store tests never touch the user's store.
ENV["DATATOOLKIT_STORE"] = mktempdir()

using DataToolkit
using Test
using Logging: NullLogger, with_logger
using Sockets

using DataToolkitCore: DataToolkitCore, STACK
using DataToolkitBase: DataToolkitBase
using DataToolkitStore: DataToolkitStore
using DataToolkitCommon: DataToolkitCommon
using DataToolkitREPL: DataToolkitREPL

# UUIDs is not a declared test dependency; reach `uuid4` through Core, which
# imports it, to mint a fresh UUID per collection without adding a dep.
const uuid4 = DataToolkitCore.uuid4

# Raw storage and passthrough loaders need no external package, so collections stay offline.
maketoml(name, uuid, value, type) = """
data_config_version = 0
uuid = "$uuid"
name = "$name"

[[num]]
uuid = "$(uuid4())"

    [[num.storage]]
    driver = "raw"
    value = $value

    [[num.loader]]
    driver = "passthrough"
    type = ["$type"]
"""

"""
    storecollection(datasets::String) -> DataCollection

Load a throwaway collection using the `store` plugin, whose TOML body (data
sets, and any `[config.store]`) is `datasets`.
"""
function storecollection(datasets::String)
    path = joinpath(mktempdir(), "Data.toml")
    write(path, """
    data_config_version = 0
    uuid = "$(uuid4())"
    name = "store$(basename(dirname(path)))"
    plugins = ["store"]

    $datasets
    """)
    loadcollection!(path)
end

"""
A local HTTP server for `web` storage tests, on an ephemeral port at
`SERVER_URL`. It serves each body in `ROUTES` at its path (any other path is
a 404), declaring the length `DECLARED_LENGTHS` gives a path in place of the
body's own, and logs each request line to `REQUESTS`.
"""
const ROUTES = Dict{String, String}()
const DECLARED_LENGTHS = Dict{String, Int}()
const REQUESTS = String[]
const SERVER_URL = let (port, server) = listenany(Sockets.localhost, 0)
    @async while true
        client = accept(server)
        @async try
            request = readline(client)
            while !isempty(readline(client)) end # headers
            push!(REQUESTS, request)
            path = split(request)[2]
            body = get(ROUTES, path, nothing)
            status = if isnothing(body) "404 Not Found" else "200 OK" end
            declared = get(DECLARED_LENGTHS, path, sizeof(something(body, "")))
            write(client, "HTTP/1.1 $status\r\nContent-Length: $declared\r\n",
                  "Connection: close\r\n\r\n", something(body, ""))
        finally
            close(client)
        end
    end
    "http://127.0.0.1:$port"
end

stack_backup = copy(STACK)
try
    @testset "Re-exports reachable through DataToolkit" begin
        for sym in (:DataCollection, :DataSet, :DataStorage, :DataLoader,
                    :DataWriter, :Identifier, :Plugin, :dataset, :getlayer)
            @test getfield(DataToolkit, sym) === getfield(DataToolkitCore, sym)
        end
        @test DataToolkit.var"@d_str" === DataToolkitBase.var"@d_str"
        @test DataToolkit.var"@require" === DataToolkitBase.var"@require"
        @test DataToolkit.var"@addpkg" === DataToolkitBase.var"@addpkg"
        @test DataToolkit.Core === DataToolkitCore
        @test DataToolkit.Store === DataToolkitStore
        @test DataToolkit.Common === DataToolkitCommon
        @test DataToolkit.Base === DataToolkitBase
        @test DataToolkit.REPL === DataToolkitREPL
        @test loadcollection! isa Function
        @test issubset(["store", "defaults", "memorise"], DataToolkit.plugins())
    end

    @testset "End-to-end: define, resolve, read (raw + passthrough)" begin
        uuid = uuid4()
        datatoml = """
        data_config_version = 0
        uuid = "$uuid"
        name = "maintest"

        [[num]]
        uuid = "$(uuid4())"

            [[num.storage]]
            driver = "raw"
            value = 42

            [[num.loader]]
            driver = "passthrough"
            type = ["Int"]

        [[greeting]]
        uuid = "$(uuid4())"

            [[greeting.storage]]
            driver = "raw"
            value = "hello"

            [[greeting.loader]]
            driver = "passthrough"
            type = ["String"]
        """
        collection = loadcollection!(IOBuffer(datatoml))
        @test collection isa DataToolkit.DataCollection
        try
            ds = dataset("maintest:num")
            @test ds isa DataToolkit.DataSet
            @test read(ds, Int) == 42
            @test read(ds) == 42
            ds2 = dataset("maintest:greeting")
            @test read(ds2, String) == "hello"
        finally
            filter!(c -> c.uuid != uuid, STACK)
        end
    end

    @testset "d\"\" macro resolves through the facade" begin
        uuid = uuid4()
        loadcollection!(IOBuffer(maketoml("dtest", uuid, 7, "Int")))
        try
            @test d"dtest:num" == 7
            @test d"dtest:num::Int" == read(dataset("dtest:num"), Int)
        finally
            filter!(c -> c.uuid != uuid, STACK)
        end
    end

    @testset "init soft-load is idempotent by UUID" begin
        uuid = uuid4()
        mktempdir() do dir
            path = joinpath(dir, "Data.toml")
            write(path, maketoml("inittest", uuid, 3, "Int"))
            try
                first_load = loadcollection!(path, Main; soft=true)
                @test first_load isa DataToolkit.DataCollection
                @test any(c -> c.uuid == uuid, STACK)
                @test loadcollection!(path, Main; soft=true) === nothing
                @test count(c -> c.uuid == uuid, STACK) == 1
            finally
                filter!(c -> c.uuid != uuid, STACK)
            end
        end
    end

    @testset "addpkgs registers declared dependencies" begin
        @test_logs (:warn,) DataToolkit.addpkgs(@__MODULE__, [:NotARealDep_XYZ])
        @test DataToolkit.addpkgs(DataToolkit, [:DataToolkitCore]) === nothing
    end

    @testset "@data_cmd errors without REPL loaded" begin
        if isempty(methods(DataToolkitREPL.toplevel_execute_repl_cmd))
            err = try
                @eval @data_cmd "list"
                nothing
            catch e
                e
            end
            @test err isa ErrorException
            @test occursin("requires the REPL", err.msg)
        end
    end

    @testset "Store through Common's drivers" begin
        @testset "A gone web storage falls through" begin
            coll = storecollection("""
            [[greeting]]
            uuid = "$(uuid4())"

                [[greeting.storage]]
                driver = "web"
                url = "$SERVER_URL/gone.txt"
                priority = 1

                [[greeting.storage]]
                driver = "filesystem"
                path = "fallback.txt"
                priority = 2

                [[greeting.loader]]
                driver = "passthrough"
            """)
            write(joinpath(dirname(coll.source.path), "fallback.txt"), "fallback")
            empty!(REQUESTS)
            @test with_logger(() -> read(dataset(coll, "greeting"), String), NullLogger()) == "fallback"
            # One fetch, of however many attempts.
            @test all(==("GET /gone.txt HTTP/1.1"), REQUESTS)
            @test 1 <= length(REQUESTS) <= 3
        end
        @testset "A download too big for its directory is refused" begin
            ROUTES["/huge.bin"], DECLARED_LENGTHS["/huge.bin"] = "x", 2^62
            storedir = mktempdir()
            coll = storecollection("""
            [config.store]
            path = "$storedir"

            [[huge]]
            uuid = "$(uuid4())"

                [[huge.storage]]
                driver = "web"
                url = "$SERVER_URL/huge.bin"
                priority = 1

                [[huge.storage]]
                driver = "filesystem"
                path = "fallback.txt"
                priority = 2

                [[huge.loader]]
                driver = "passthrough"

            [[unstored]]
            uuid = "$(uuid4())"

                [[unstored.storage]]
                driver = "web"
                url = "$SERVER_URL/huge.bin"
                save = false

                [[unstored.loader]]
                driver = "passthrough"
            """)
            write(joinpath(dirname(coll.source.path), "fallback.txt"), "fallback")
            refusal(name) = DataToolkitCore.unwrap_logtask(
                try with_logger(() -> open(dataset(coll, name), DataToolkitCore.FilePath), NullLogger()); nothing catch e; e end)
            empty!(REQUESTS)
            stored = refusal("huge")
            @test stored isa DataToolkitCommon.InsufficientSpace && stored.needed == 2^62
            @test stored.directory == joinpath(storedir, "store") && REQUESTS == ["GET /huge.bin HTTP/1.1"]
            @test isempty(readdir(stored.directory))
            unstored = refusal("unstored")
            @test unstored isa DataToolkitCommon.InsufficientSpace && dirname(unstored.directory) == tempdir()
        end
        @testset "A download is moved into place" begin
            ROUTES["/staged.txt"] = "staged\n"
            stagedsum = string(DataToolkitStore.checksum(:sha256, "staged\n"))
            storedir = mktempdir()
            coll = storecollection("""
            [config.store]
            path = "$storedir"

            [[checksummed]]
            uuid = "$(uuid4())"

                [[checksummed.storage]]
                driver = "web"
                url = "$SERVER_URL/staged.txt"
                checksum = "$stagedsum"

                [[checksummed.loader]]
                driver = "passthrough"

            [[computed]]
            uuid = "$(uuid4())"

                [[computed.storage]]
                driver = "web"
                url = "$SERVER_URL/staged.txt"
                checksum = "sha256"

                [[computed.loader]]
                driver = "passthrough"
            """)
            # Anything under `tempdir()`, which holds the store here, is moved.
            withenv("TMPDIR" => mktempdir()) do
                @test read(dataset(coll, "checksummed"), String) == "staged\n"
                @test read(dataset(coll, "computed"), String) == "staged\n"
            end
            @test readdir(joinpath(storedir, "store")) == ["$stagedsum.txt"]
        end
        @testset "The filesystem driver manages only its own links" begin
            ROUTES["/shared.txt"] = "shared\n"
            sharedsum = string(DataToolkitStore.checksum(:sha256, "shared\n"))
            storedir = mktempdir()
            coll = storecollection("""
            [config.store]
            path = "$storedir"

            [[download]]
            uuid = "$(uuid4())"

                [[download.storage]]
                driver = "web"
                url = "$SERVER_URL/shared.txt"
                checksum = "$sharedsum"

                [[download.loader]]
                driver = "passthrough"

            [[copy]]
            uuid = "$(uuid4())"

                [[copy.storage]]
                driver = "filesystem"
                path = "copy.txt"
                checksum = "$sharedsum"

                [[copy.loader]]
                driver = "passthrough"
            """)
            localcopy = joinpath(dirname(coll.source.path), "copy.txt")
            write(localcopy, "shared\n")
            stored = joinpath(storedir, "store", "$sharedsum.txt")
            @test read(dataset(coll, "download"), String) == "shared\n"
            @test read(dataset(coll, "copy"), String) == "shared\n"
            @test isfile(stored) && !islink(stored)
            write(localcopy, "edited\n")
            copystorage = only(dataset(coll, "copy").storage)
            @test DataToolkitStore.storefile(DataToolkitStore.getinventory!(coll), copystorage) == stored
            @test read(dataset(coll, "download"), String) == "shared\n"
        end
        @testset "A link whose target changed is checked again" begin
            # The two files share one link, to whichever was read first.
            origsum = string(DataToolkitStore.checksum(:sha256, "original\n"))
            storedir = mktempdir()
            localfile(name) = storecollection("""
            [config.store]
            path = "$storedir"

            [[local]]
            uuid = "$(uuid4())"

                [[local.storage]]
                driver = "filesystem"
                path = "$name.txt"
                checksum = "$origsum"

                [[local.loader]]
                driver = "passthrough"
            """)
            edited, other = localfile("edited"), localfile("other")
            write(joinpath(dirname(edited.source.path), "edited.txt"), "original\n")
            write(joinpath(dirname(other.source.path), "other.txt"), "original\n")
            @test read(dataset(edited, "local"), String) == "original\n"
            @test read(dataset(other, "local"), String) == "original\n"
            write(joinpath(dirname(edited.source.path), "edited.txt"), "EDITED\n")
            err = try read(dataset(edited, "local"), String); nothing catch e; e end
            @test DataToolkitCore.unwrap_logtask(err) isa DataToolkitStore.ChecksumMismatch
            @test read(dataset(other, "local"), String) == "original\n"
        end
        @testset "Local files without a checksum are told apart by path" begin
            # `checksum = true` names no value, so it can't stand for the path.
            coll = storecollection("""
            [[one]]
            uuid = "$(uuid4())"

                [[one.storage]]
                driver = "filesystem"
                path = "one.txt"
                checksum = true

                [[one.loader]]
                driver = "passthrough"

            [[two]]
            uuid = "$(uuid4())"

                [[two.storage]]
                driver = "filesystem"
                path = "two.txt"
                checksum = true

                [[two.loader]]
                driver = "passthrough"
            """)
            write(joinpath(dirname(coll.source.path), "one.txt"), "one")
            write(joinpath(dirname(coll.source.path), "two.txt"), "two")
            @test read(dataset(coll, "one"), String) == "one"
            @test read(dataset(coll, "two"), String) == "two"
        end
        @testset "A null storage is read, never stored" begin
            coll = storecollection("""
            [config.store]
            path = "$(mktempdir())"

            [[answer]]
            uuid = "$(uuid4())"

                [[answer.storage]]
                driver = "null"

                [[answer.loader]]
                driver = "julia"
                function = "() -> 42"
                type = "Int"
            """)
            @test read(dataset(coll, "answer"), Int) == 42
            DataToolkitStore.fetch!(coll)
            @test isempty(DataToolkitStore.getinventory!(coll).stores)
        end
    end

    include("e2e_repl.jl")
finally
    empty!(STACK)
    append!(STACK, stack_backup)
end
