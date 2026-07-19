# Keep the auto-init walk of the ambient load path from mutating the shared
# global STACK before the suite starts. Must be set before `using DataToolkit`.
ENV["DATA_TOOLKIT_AUTO_INIT"] = "no"

using DataToolkit
using Test

using DataToolkitCore: DataToolkitCore, STACK
using DataToolkitBase: DataToolkitBase
using DataToolkitStore: DataToolkitStore
using DataToolkitCommon: DataToolkitCommon
using DataToolkitREPL: DataToolkitREPL

# UUIDs is not a declared test dependency; reach `uuid4` through Core, which
# imports it, to mint a fresh UUID per collection without adding a dep.
const uuid4 = DataToolkitCore.uuid4

# A raw+passthrough Data.toml requires no external package, so collections stay
# fully offline. `value`/`type` drive the raw storage and passthrough loader.
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
                # A second soft-load of the same UUID is a no-op.
                @test loadcollection!(path, Main; soft=true) === nothing
                @test count(c -> c.uuid == uuid, STACK) == 1
            finally
                filter!(c -> c.uuid != uuid, STACK)
            end
        end
    end

    @testset "addpkgs registers declared dependencies" begin
        @test_logs (:warn,) DataToolkit.addpkgs(@__MODULE__, [:NotARealDep_XYZ])
        # A real dep of Main's Project.toml registers without error.
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
finally
    empty!(STACK)
    append!(STACK, stack_backup)
end
