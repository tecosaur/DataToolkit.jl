using PrecompileTools

precompile(__init__, ())

@setup_workload begin
    nulldisp = TextDisplay(devnull)
    pushdisplay(nulldisp)
    datatoml = """
    data_config_version = 0
    uuid = "84068d44-24db-4e28-b693-58d2e1f59d05"
    name = "precompile"
    plugins = ["store", "cache", "defaults", "log", "versions", "memorise"]

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
        redirect_stdio(stdout=devnull, stderr=devnull) do
            config_set("defaults.something 1")
            config_get("defaults")
            config_unset("defaults")
            repl_list("")
            search("data")
            plugin_remove("defaults")
            plugin_add("defaults")
            plugin_list("")
            repl_show("dataset")
            stack_list("")
            stack_promote("")
            stack_demote("")
        end
    end
    popdisplay(nulldisp)
end
