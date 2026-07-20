# Terminal-driven golden tests of the Data REPL's prompt layer. TRT captures only
# what is written to its emulated terminal, which is why the REPL takes an
# explicit `io`. Regenerate goldens with REGEN=1. Skipped on Julia 1.12+ until
# TRT's VT100 dependency supports it (JuliaDebug/TerminalRegressionTests.jl#24).

@static if VERSION < v"1.12"
    using TerminalRegressionTests

    const GOLDEN_DIR = joinpath(@__DIR__, "golden")

    # Drive `driver(io)` at an emulated terminal fed `inputs`, compare it with
    # golden/<name>.multiout (REGEN=1 writes it), and return what `driver` gave.
    function dtk_golden(driver, name, inputs)
        golden = joinpath(GOLDEN_DIR, name * ".multiout")
        result = Ref{Any}(nothing)
        capture = io -> (result[] = driver(io))
        if get(ENV, "REGEN", "") == "1"
            mkpath(GOLDEN_DIR)
            TerminalRegressionTests.create_automated_test(capture, golden, inputs)
        else
            TerminalRegressionTests.automated_test(capture, golden, inputs)
        end
        result[]
    end

    @testset "prompt primitives (terminal-driven)" begin
        cases = [
            # (golden name, fed inputs, driver, expected return)
            ("prompt-basic", ["Ada\r"],
             io -> M.prompt(io, "Name? "), "Ada"),
            ("prompt-default", ["\r"],
             io -> M.prompt(io, "Colour? ", "blue"), "blue"),
            ("prompt-allowempty", ["\r"],
             io -> M.prompt(io, "Optional? "; allowempty=true), ""),
            ("confirm-yes", ["y"],
             io -> M.confirm_yn(io, "Proceed?", false), true),
            ("confirm-default-true", ["\r"],
             io -> M.confirm_yn(io, "Proceed?", true), true),
            ("promptchar-option", ["a"],
             io -> M.prompt_char(io, "Pick: ", ['a', 'b']), 'a'),
        ]
        for (name, inputs, driver, expected) in cases
            @testset "$name" begin
                @test dtk_golden(driver, name, inputs) == expected
            end
        end
    end
end
