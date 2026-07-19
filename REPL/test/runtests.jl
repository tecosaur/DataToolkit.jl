using DataToolkitREPL, REPL
using DataToolkitCore: loadcollection!, STACK, config_get, natkeygen
using Test

# Non-exported REPLMode internals live in the package extension, which only
# materialises once `using REPL` has run (above).
const M = Base.get_extension(DataToolkitREPL, :REPLMode)

# Minimal, transformer-free collection used by the completion and command
# round-trip groups. `writable` writes to a tempfile (0o644) so config
# set/unset persists; otherwise it loads from an IOBuffer (no disk write).
# STACK is always restored, and any tempfile removed, in the `finally`.
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
    tlx(line) = redirect_stdio(() -> DataToolkitREPL.toplevel_execute_repl_cmd(line);
                               stdout = devnull, stderr = devnull)
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
    # An unterminated quote where the only closing quote is escaped must not
    # index past the end of the string.
    @test peelword("\"name\\\"") isa Tuple{String, String}
    # A dot binds into the word when `allowdot`, but splits the word otherwise.
    @test peelword("a.b c") == ("a.b", "c")
    @test peelword("a.b c", allowdot=false) == ("a", ".b c")
    # Leading and inter-word whitespace is collapsed; trailing is retained.
    @test peelword("  one   two  ") == ("one", "two  ")
    # An escaped quote inside a quoted word is unescaped, not treated as the end.
    @test peelword("\"esc\\\"aped\" rest") == ("esc\"aped", "rest")
    # Without a closing quote, the leading `"` is kept and bareword rules apply.
    @test peelword("\"unterm rest") == ("\"unterm", "rest")
    # One whitespace char after the closing quote is consumed.
    @test peelword("\"quoted word\" after") == ("quoted word", "after")
end

@testset "parse_repl_value (TOML value parsing)" begin
    # Pure TOML literals keep their native type.
    @test M.parse_repl_value("42") === 42
    @test M.parse_repl_value("3.14") === 3.14
    @test M.parse_repl_value("true") === true
    @test M.parse_repl_value("false") === false
    @test M.parse_repl_value("[1,2,3]") == [1, 2, 3]
    @test M.parse_repl_value("{a=1}") == Dict("a" => 1)
    # Barewords are quoted into strings, and explicit quotes are unwrapped.
    @test M.parse_repl_value("hello") == "hello"
    @test M.parse_repl_value("\"quoted\"") == "quoted"
    @test M.parse_repl_value("") == ""
    # A dotted bareword is neither a valid literal nor valid once quoted.
    @test M.parse_repl_value("1.2.3") === nothing
end

@testset "config_segments dotted-path parsing" begin
    @test M.config_segments("a.b.c") == (["a", "b", "c"], "")
    # A quoted segment may carry spaces (and dots) without splitting.
    @test M.config_segments("a.\"b c\".d rest") == (["a", "b c", "d"], "rest")
    # The value trailing the path is returned separately from the segments.
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
        # `remove` on a read-only collection must not delete the dataset from
        # the in-memory collection (the on-disk file cannot be updated).
        redirect_stdio(stdin = devnull, stdout = devnull, stderr = devnull) do
            DataToolkitREPL.toplevel_execute_repl_cmd("remove victim")
        end
        @test any(d -> d.name == "victim", collection.datasets)
    finally
        filter!(!=(collection), STACK)
        chmod(path, 0o644)
        rm(path, force=true)
    end
end

@testset "completion helpers against a loaded collection" begin
    with_temp_collection(REPLTEST_TOML) do collection
        # The collection name completes on a matching prefix, not otherwise.
        @test "repltest" ∈ M.complete_collection("")
        @test isempty(M.complete_collection("no"))
        # A dataset prefix returns exactly the matching names.
        al = M.complete_dataset("al")
        @test "alpha" ∈ al && "alto" ∈ al
        @test "beta" ∉ al
        # An empty prefix surfaces every dataset (bare and collection-scoped).
        all_ds = M.complete_dataset("")
        @test all(n -> n ∈ all_ds, ("alpha", "beta", "alto"))
        @test "repltest:alpha" ∈ all_ds
        # The combined helper is a superset spanning both collection and datasets.
        combined = M.complete_dataset_or_collection("")
        @test "repltest" ∈ combined
        @test all(n -> n ∈ combined, ("alpha", "beta", "alto"))
        @test issorted(combined, by=natkeygen)
    end
end

@testset "command round-trips via toplevel_execute_repl_cmd" begin
    tlx(line) = redirect_stdio(() -> DataToolkitREPL.toplevel_execute_repl_cmd(line);
                               stdin=devnull, stdout=devnull, stderr=devnull)
    with_temp_collection(REPLTEST_TOML; writable=true) do collection
        # Listing and showing existing entities complete without escaping.
        @test isnothing(tlx("list"))
        @test isnothing(tlx("list repltest"))
        @test isnothing(tlx("show alpha"))
        @test isnothing(tlx("stack"))
        @test isnothing(tlx("stack list"))
        # A config set/unset round-trip is observable in the collection state.
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
    # A unique prefix resolves; an ambiguous one (show/search/stack) does not.
    @test M.find_repl_cmd("li").name == "list"
    @test isnothing(M.find_repl_cmd("s"))
end
