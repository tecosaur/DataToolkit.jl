using DataToolkitREPL, REPL
using DataToolkitCore: loadcollection!, STACK
using Test

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
