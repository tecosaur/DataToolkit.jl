using PrecompileTools

precompile(__init__, ())

@setup_workload begin
    struct FakeTerminal <: REPL.Terminals.UnixTerminal
        in_stream::IOBuffer
        out_stream::IOBuffer
        err_stream::IOBuffer
        hascolor::Bool
        raw::Bool
        FakeTerminal() = new(IOBuffer(), IOBuffer(), IOBuffer(), false, true)
    end
    REPL.raw!(::FakeTerminal, raw::Bool) = raw
    term = FakeTerminal()
    local repl
    try
        repl = REPL.LineEditREPL(term, true)
        REPL.run_repl(repl)
    catch _
    end
    nulldisp = TextDisplay(devnull)
    pushdisplay(nulldisp)
    datatoml = """
    data_config_version = 0
    uuid = "84068d44-24db-4e28-b693-58d2e1f59d05"
    name = "precompile"
    plugins = []

    [[dataset]]
    uuid = "d9826666-5049-4051-8d2e-fe306c20802c"

        [[dataset.storage]]
            driver = "raw"
            value = 3
            type = "Int"

        [[dataset.loader]]
            driver = "passthrough"
            type = "Int"
    """
    loadcollection!(IOBuffer(datatoml))
    @compile_workload begin
        __init__()
        init_repl(repl)
        redirect_stdio(stdout=devnull, stderr=devnull) do
            toplevel_execute_repl_cmd("?")
            toplevel_execute_repl_cmd("?help")
            toplevel_execute_repl_cmd("help help")
            toplevel_execute_repl_cmd("help :")
        end
        complete_repl_cmd("help ")
        redirect_stdio(stdout=devnull, stderr=devnull) do
            config_set("defaults.something 1")
            config_get("defaults")
            config_unset("defaults")
            repl_list("")
            search("data")
            # plugin_remove("defaults")
            # plugin_add("defaults")
            plugin_list("")
            repl_show("dataset")
            stack_list("")
            stack_promote("")
            stack_demote("")
        end
    end
    popdisplay(nulldisp)
end
