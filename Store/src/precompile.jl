using PrecompileTools

@setup_workload begin
    invtoml = """
    inventory_version = $INVENTORY_VERSION
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
    typehashes = ["$(string(rhash(Int), base=16))"]

        [[cache.packages]]
        name = "InlineStrings"
        uuid = "842dd82b-1e85-43dc-bf29-5d0ee9dffc48"
    """
    @compile_workload begin
        __init__()
        empty!(INVENTORIES)
        tmpdir = mktempdir()
        tmpfile = joinpath(tmpdir, INVENTORY_FILENAME)
        write(tmpfile, invtoml)
        inv = BaseDirs.@promise_no_assign load_inventory(tmpfile)
        push!(INVENTORIES, inv)
        # merkle(inv.merkles, @__DIR__, ".", :crc32c)
        write(devnull, last(INVENTORIES))
        garbage_collect!(; log=false, trimmsg=false, dryrun=false)
        rhash(Inventory)
        rhash(first(INVENTORIES))
        pop!(INVENTORIES)
    end
    empty!(INVENTORIES)
end
