import DataToolkitBase: allcompletions

const REPL_CONFIG_KEYS = ["auto_gc", "max_age", "max_size", "recency_beta", "store_dir", "cache_dir"]

function repl_config_get(input::AbstractString)
    inventory = if isempty(STACK)
        getinventory()
    else
        getinventory(first(STACK))
    end |> update_inventory!
    value_sets = [(:auto_gc, "hours"),
                  (:max_age, "days"),
                  (:max_size, s ->
                      if isnothing(s) "-" else join(humansize(s)) end),
                  (:recency_beta, ""),
                  (:store_dir, ""),
                  (:cache_dir, "")]
    if !isempty(input)
        filter!((v, _)::Tuple -> String(v) == input, value_sets)
        if isempty(value_sets)
            printstyled(" ! ", color=:red, bold=true)
            println("'$input' is not a valid configuration parameter")
            return
        end
    end
    for (param, printer) in value_sets
        printstyled("  ", param, color=:cyan)
        value = getproperty(inventory.config, param)
        default = getproperty(DEFAULT_INVENTORY_CONFIG, param)
        if printer isa Function
            print(' ', printer(value))
        elseif isempty(printer)
            print(' ', value)
        else
            print(" $value $printer")
        end
        if value == default
            printstyled(" (default)", color=:light_black)
        else
            dstr = if printer isa Function
                printer(default)
            else default end
            printstyled(" ($dstr by default)", color=:light_black)
        end
        print('\n')
    end
end

function repl_config_set(input::AbstractString)
    inventory = if isempty(STACK)
        getinventory()
    else
        getinventory(first(STACK))
    end
    if !any(isspace, input)
        printstyled(" ! ", color=:red, bold=true)
        println("must provide a \"{parameter} {value}\" form")
        return
    end
    setters = Dict(
        "auto_gc" => (field = :auto_gc, type = Int, noval = "-"),
        "max_age" => (field = :max_age, type = Int, noval = "-"),
        "max_size" => (field = :max_size, type = :bytes, noval = "-"),
        "recency_beta" => (field = :recency_beta, type = Number),
        "store_dir" => (field = :store_dir, type = String),
        "cache_dir" => (field = :cache_dir, type = String))
    param, value = split(input, limit=2)
    if haskey(setters, param)
        setter = setters[param]
        setval = if hasproperty(setter, :noval) && value == setter.noval
            Some(nothing)
        elseif setter.type == String
            value
        elseif setter.type == Int
            tryparse(Int, value)
        elseif setter.type == Number
            something(tryparse(Int, value), parse(Float64, value))
        elseif setter.type == :bytes
            try
                parsebytesize(value)
            catch err
                if !(err isa ArgumentError)
                    rethrow()
                end
            end
        end
        if !isnothing(setval)
            update_inventory!(inventory)
            setproperty!(inventory.config, setter.field, something(setval))
            write(inventory)
            printstyled(" ✓ Done\n", color=:green)
        else
            printstyled(" ! ", color=:red, bold=true)
            println(if setter.type == :bytes
                        "must be a byte size (e.g. '5GiB', '100kB')"
                    elseif setter.type == Int
                        "must be an integer"
                    elseif setter.type == Number
                        "must be a number"
                    end)
        end
    else
        printstyled(" ! ", color=:red, bold=true)
        println("unrecognised parameter: $param")
    end
end

function repl_config_reset(input::AbstractString)
    inventory = if isempty(STACK)
        getinventory()
    else
        getinventory(first(STACK))
    end
    printers = Dict(
        "auto_gc" => v -> if v <= 0 "off" else string(v, " hours") end,
        "max_age" => v -> string(v, " days"),
        "max_size" => v -> if isnothing(v) "unlimited" else join(humansize(v)) end)
    if input in REPL_CONFIG_KEYS
        printer = get(printers, input, identity)
        update_inventory!(inventory)
        default_value = getproperty(DEFAULT_INVENTORY_CONFIG, Symbol(input))
        setproperty!(inventory.config, Symbol(input), default_value)
        write(inventory)
        printstyled(" ✓ ", color=:green)
        println("Set to ", printer(default_value))
    else
        printstyled(" ! ", color=:red, bold=true)
        println("unrecognised parameter: $input")
        return
    end
end

allcompletions(::ReplCmd{:store_config_get}) = REPL_CONFIG_KEYS
allcompletions(::ReplCmd{:store_config_set}) = REPL_CONFIG_KEYS
allcompletions(::ReplCmd{:store_config_reset}) = REPL_CONFIG_KEYS

function repl_gc(input::AbstractString)
    flags = split(input)
    dryrun = "-d" in flags || "--dryrun" in flags
    if "-a" in flags || "--all" in flags
        garbage_collect!(; dryrun)
    else
        inventory = if isempty(STACK) getinventory()
        else getinventory(first(STACK)) end |> update_inventory!
        garbage_collect!(inventory; dryrun)
    end
end

allcompletions(::ReplCmd{:store_gc}) = ["-d", "--dryrun", "-a", "--all"]

function repl_expunge(input::AbstractString)
    inventory = if isempty(STACK) getinventory()
    else getinventory(first(STACK)) end |> update_inventory!
    collection = nothing
    for cltn in inventory.collections
        if cltn.name == input
            collection = cltn
        elseif string(cltn.uuid) == input
            collection = cltn
        end
        isnothing(collection) || break
    end
    if isnothing(collection)
        printstyled(" ! ", color=:red, bold=true)
        println("could not find collection in store: $input")
        return
    end
    removed = expunge!(inventory, collection)
    printstyled(" i ", color=:cyan, bold=true)
    println("removed $(length(removed)) items from the store")
end

function allcompletions(::ReplCmd{:store_expunge})
    inventory = if isempty(STACK) getinventory()
    else getinventory(first(STACK)) end
    getfield.(inventory.collections, :name)
end

function repl_fetch(input::AbstractString)
    if isempty(STACK)
        printstyled(" ! ", color=:yellow, bold=true)
        println("The data collection stack is empty")
    elseif isempty(input)
        foreach(fetch!, STACK)
    else
        try
            collection = DataToolkitBase.getlayer(
                @something(tryparse(Int, input),
                           tryparse(UUID, input),
                           String(input)))
            fetch!(collection)
        catch
            dataset = resolve(input, resolvetype=false)
            fetch!(dataset)
        end
    end
end

const STORE_SUBCMDS =
    ReplCmd[
        ReplCmd{:store_config}(
            "config", "Manage configuration",
            ReplCmd[
                ReplCmd{:store_config_get}(
                    "get", MD(md"Get the current configuration",
                              STORE_GC_CONFIG_INFO),
                    repl_config_get),
                ReplCmd{:store_config_set}(
                    "set", MD(md"Set a configuration parameter",
                              STORE_GC_CONFIG_INFO),
                    repl_config_set),
                ReplCmd{:store_config_reset}(
                    "reset", MD(md"Set a configuration parameter",
                                STORE_GC_CONFIG_INFO),
                    repl_config_reset)]),
        ReplCmd{:store_expunge}(
            "expunge",
            md"""Remove a data collection from the store
                 ## Usage

                     data> expunge [collection name or UUID]""",
            repl_expunge),
        ReplCmd{:store_fetch}(
            "fetch",
            md"""Fetch data storage sources

               A particular collection or data set can be specified with

                   data> fetch [collection or data set name or UUID]

               Without specifying a particular target, all data sets
               are fetched.""",
            repl_fetch),
        ReplCmd{:store_gc}(
            "gc",
            md"""Garbage Collect

                 Scan the inventory and perform a garbage collection sweep.

                 Optionally provide the `-d`/`--dryrun` flag to prevent
                 file deletion.""",
            repl_gc),
        ReplCmd{:store_stats}(
            "stats", "Show statistics about the data store",
            function (_)
                update_inventory!.(INVENTORIES)
                printstats()
            end)]

const STORE_REPL_CMD =
    ReplCmd(:store,
            "Manipulate the data store",
            STORE_SUBCMDS)
