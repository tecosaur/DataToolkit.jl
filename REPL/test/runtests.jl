using DataToolkitREPL, REPL
using DataToolkitCore: loadcollection!, STACK, config_get, natkeygen
using Test

# Non-exported REPLMode internals live in the package extension, which only
# materialises once `using REPL` has run (above).
const M = Base.get_extension(DataToolkitREPL, :REPLMode)

# A transformer-free collection; `writable` backs it with a tempfile so config
# set/unset persists. STACK is restored in the `finally`.
function with_temp_collection(f, toml::AbstractString; writable::Bool=false)
    if writable
        path = tempname() * ".toml"
        write(path, toml)
        chmod(path, 0o644)
        collection = loadcollection!(path)
        try
            f(collection)
        finally
            filter!(!=(collection), STACK)
            chmod(path, 0o644)
            rm(path, force=true)
        end
    else
        collection = loadcollection!(IOBuffer(toml))
        try
            f(collection)
        finally
            filter!(!=(collection), STACK)
        end
    end
end

const REPLTEST_TOML = """
data_config_version = 0
uuid = "2d70ad35-a766-4a14-c802-a4f04bfd6ef3"
name = "repltest"

[[alpha]]
uuid = "9d23f7c5-7a98-55fa-b44e-89f627f26913"
description = "first"

[[beta]]
uuid = "9d23f7c5-7a98-55fa-b44e-89f627f26914"
description = "second"

[[alto]]
uuid = "9d23f7c5-7a98-55fa-b44e-89f627f26915"
description = "third"
"""

@testset "Command error containment" begin
    # Nothing may escape `toplevel_execute_repl_cmd`: an uncaught exception
    # kills the whole REPL session (LineEdit runs it outside any try/catch)
    tlx(line) = DataToolkitREPL.toplevel_execute_repl_cmd(devnull, line)
    @test isnothing(tlx("list nothere"))
    @test isnothing(tlx("config get"))
    @test isnothing(tlx("config set data_config_version bad?input"))
    @test isnothing(tlx("show nosuchdataset"))
    @test isnothing(tlx("edit nosuchdataset"))
    @test isnothing(tlx("remove nosuchdataset"))
    @test isnothing(tlx("stack promote nothere"))
end

@testset "peelword (R7)" begin
    peelword = DataToolkitREPL.peelword
    @test peelword("one two") == ("one", "two")
    @test peelword("\"one two\" three") == ("one two", "three")
    @test peelword("") == ("", "")
    @test peelword("\"name\\\"") isa Tuple{String, String}
    @test peelword("a.b c") == ("a.b", "c")
    @test peelword("a.b c", allowdot=false) == ("a", ".b c")
    @test peelword("  one   two  ") == ("one", "two  ")
    @test peelword("\"esc\\\"aped\" rest") == ("esc\"aped", "rest")
    @test peelword("\"unterm rest") == ("\"unterm", "rest")
    @test peelword("\"quoted word\" after") == ("quoted word", "after")
end

@testset "parse_repl_value (TOML value parsing)" begin
    @test M.parse_repl_value("42") === 42
    @test M.parse_repl_value("3.14") === 3.14
    @test M.parse_repl_value("true") === true
    @test M.parse_repl_value("false") === false
    @test M.parse_repl_value("[1,2,3]") == [1, 2, 3]
    @test M.parse_repl_value("{a=1}") == Dict("a" => 1)
    @test M.parse_repl_value("hello") == "hello"
    @test M.parse_repl_value("\"quoted\"") == "quoted"
    @test M.parse_repl_value("") == ""
    @test M.parse_repl_value("1.2.3") === nothing
end

@testset "config_segments dotted-path parsing" begin
    @test M.config_segments("a.b.c") == (["a", "b", "c"], "")
    @test M.config_segments("a.\"b c\".d rest") == (["a", "b c", "d"], "rest")
    @test M.config_segments("defaults.memorise true") ==
        (["defaults", "memorise"], "true")
    @test M.config_segments("") == (String[], "")
end

@testset "remove on read-only collection (R10)" begin
    datatoml = """
    data_config_version = 0
    uuid = "2d70ad35-a766-4a14-c802-a4f04bfd6ef2"
    name = "rotest"

    [[victim]]
    uuid = "9d23f7c5-7a98-55fa-b44e-89f627f26912"
    """
    path = tempname() * ".toml"
    write(path, datatoml)
    chmod(path, 0o444)
    collection = loadcollection!(path)
    try
        @test !iswritable(collection)
        DataToolkitREPL.toplevel_execute_repl_cmd(devnull, "remove victim")
        @test any(d -> d.name == "victim", collection.datasets)
    finally
        filter!(!=(collection), STACK)
        chmod(path, 0o644)
        rm(path, force=true)
    end
end

@testset "completion helpers against a loaded collection" begin
    with_temp_collection(REPLTEST_TOML) do collection
        @test "repltest" ∈ M.complete_collection("")
        @test isempty(M.complete_collection("no"))
        al = M.complete_dataset("al")
        @test "alpha" ∈ al && "alto" ∈ al
        @test "beta" ∉ al
        all_ds = M.complete_dataset("")
        @test all(n -> n ∈ all_ds, ("alpha", "beta", "alto"))
        @test "repltest:alpha" ∈ all_ds
        combined = M.complete_dataset_or_collection("")
        @test "repltest" ∈ combined
        @test all(n -> n ∈ combined, ("alpha", "beta", "alto"))
        @test issorted(combined, by=natkeygen)
    end
end

@testset "command round-trips via toplevel_execute_repl_cmd" begin
    tlx(line) = DataToolkitREPL.toplevel_execute_repl_cmd(devnull, line)
    with_temp_collection(REPLTEST_TOML; writable=true) do collection
        @test isnothing(tlx("list"))
        @test isnothing(tlx("list repltest"))
        @test isnothing(tlx("show alpha"))
        @test isnothing(tlx("stack"))
        @test isnothing(tlx("stack list"))
        tlx("config set testkey 42")
        @test config_get(collection, ["testkey"]) == 42
        tlx("config unset testkey")
        @test !haskey(collection.parameters, "testkey")
    end
end

@testset "complete_repl_cmd top-level dispatch" begin
    cands, _, should_complete = M.complete_repl_cmd("")
    @test should_complete
    @test all(n -> n ∈ cands, ("list", "show", "config", "help"))
    config_cands, _, _ = M.complete_repl_cmd("co")
    @test "config " ∈ config_cands
    @test M.find_repl_cmd(devnull, "li").name == "list"
    @test isnothing(M.find_repl_cmd(devnull, "s"))
end

include("trt_tests.jl")
