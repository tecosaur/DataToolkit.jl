using DataToolkitREPL, REPL
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
