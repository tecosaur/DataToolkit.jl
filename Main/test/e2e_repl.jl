# Full-stack, terminal-driven end-to-end tests of the Data REPL, through real
# (offline) transformers. Goldens in `test/golden/` anchor the prompt frames;
# regenerate them with REGEN=1. Skipped on Julia 1.12+ until TRT's VT100
# dependency supports it (JuliaDebug/TerminalRegressionTests.jl#24).

@static if VERSION < v"1.12"
    using REPL
    using TerminalRegressionTests
    using DataToolkitCore: driverof

    const GOLDEN_DIR = joinpath(@__DIR__, "golden")
    const tlx = DataToolkitREPL.toplevel_execute_repl_cmd

    # Type `cmd`, feeding `inputs` (one per prompt), and compare the rendered
    # frames with golden/<name>.multiout (REGEN=1 writes it instead).
    function trt_cmd(name, cmd, inputs)
        golden = joinpath(GOLDEN_DIR, name * ".multiout")
        run = io -> tlx(io, cmd)
        if get(ENV, "REGEN", "") == "1"
            mkpath(GOLDEN_DIR)
            TerminalRegressionTests.create_automated_test(run, golden, inputs)
        else
            TerminalRegressionTests.automated_test(run, golden, inputs)
        end
    end

    @testset "End-to-end via the terminal: init, add, restart (#63)" begin
        dir = mktempdir()
        path = joinpath(dir, "e2e.toml")
        empty!(STACK)
        try
            # `init <path>.toml` prompts once for the collection name (default
            # derived from the filename); RET accepts "e2e".
            trt_cmd("e2e-init", "init " * path, ["\r"])
            @test length(STACK) == 1
            @test isfile(path)
            @test first(STACK).name == "e2e"
            # `add` prompts for a description then an attribute; both empty. The
            # raw storage auto-creates from the literal source; no loader driver
            # auto-creates for a bare value, so the data set is storage-only.
            trt_cmd("e2e-add", "add num via -s raw -l passthrough from 42", ["\r", "\r"])
            num = only(first(STACK).datasets)
            @test num.name == "num"
            @test driverof.(num.storage) == [:raw]
            # Restart: drop the in-memory stack and reload purely from disk.
            empty!(STACK)
            reloaded = loadcollection!(path)
            @test reloaded.name == "e2e"
            @test dataset("num") isa DataToolkit.DataSet
        finally
            empty!(STACK)
        end
    end
end
