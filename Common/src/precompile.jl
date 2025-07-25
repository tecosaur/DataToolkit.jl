@setup_workload begin
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
    @compile_workload begin
        __init__()
        loadcollection!(IOBuffer(datatoml))
    end
    # Cleanup
    empty!(STACK)
    empty!(PLUGINS)
    empty!(PLUGINS_DOCUMENTATION)
    empty!(DEFAULT_PLUGINS)
    empty!(DataToolkitCore.EXTRA_PACKAGES)
end
