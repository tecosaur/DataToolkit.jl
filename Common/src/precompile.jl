@setup_workload begin
    invtoml = """
    inventory_version = $(Store.INVENTORY_VERSION)
    inventory_last_gc = 1970-01-01T00:00:00.000Z

    [collections.00000000-0000-0000-0000-000000000001]
    name = "demo"
    path = "nonexistant"
    seen = $(now())

    [[store]]
    recipe = "0000000000000002"
    accessed = $(now())
    references = ["00000000-0000-0000-0000-000000000001"]
    checksum = "crc32c:00000000"
    extension = "txt"

    [[cache]]
    recipe = "0000000000000003"
    accessed = $(now())
    references = ["00000000-0000-0000-0000-000000000001"]
    types = ["Int"]
    typehashes = ["$(string(Store.rhash(Int), base=16))"]

        [[cache.packages]]
        name = "InlineStrings"
        uuid = "842dd82b-1e85-43dc-bf29-5d0ee9dffc48"
    """
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
        Store.__init__()
        empty!(Store.INVENTORIES)
        __init__()
        # Store
        tempfile, tempio = mktemp()
        write(tempio, invtoml)
        close(tempio)
        push!(Store.INVENTORIES, Store.load_inventory(tempfile))
        write(IOBuffer(), last(Store.INVENTORIES))
        Store.garbage_collect!(; log=false, trimmsg=false, dryrun=true)
        Store.rhash(Store.Inventory)
        Store.rhash(first(Store.INVENTORIES))
        pop!(Store.INVENTORIES)
        # Plugins
        loadcollection!(IOBuffer(datatoml))
    end
    # Cleanup
    empty!(STACK)
    empty!(PLUGINS)
    empty!(PLUGINS_DOCUMENTATION)
    empty!(DEFAULT_PLUGINS)
    empty!(DataToolkitBase.EXTRA_PACKAGES)
    empty!(REPL_CMDS)
    empty!(Store.INVENTORIES)
end
