import DataToolkitBase: allcompletions

function repl_config_get(input::AbstractString)
    update_inventory()
    value_sets = [(:max_age, "days"),]
    if !isempty(input)
        filter!((v, _)::Tuple -> String(v) == input, value_sets)
        if isempty(value_sets)
            printstyled(" ! ", color=:red, bold=true)
            println("'$input' is not a valid configuration parameter")
            return
        end
    end
    for (param, unit) in value_sets
        printstyled("  ", param, color=:cyan)
        value = getproperty(INVENTORY.config, param)
        default = getproperty(DEFAULT_INVENTORY_CONFIG, param)
        print(" $value $unit")
        if value == default
            printstyled(" (default)", color=:light_black)
        else
            printstyled(" ($default by default)", color=:light_black)
        end
        print('\n')
    end
end

function repl_config_set(input::AbstractString)
    if !any(isspace, input)
        printstyled(" ! ", color=:red, bold=true)
        println("must provide a \"{parameter} {value}\" form")
        return
    end
    param, value = split(input, limit=2)
    if param == "max_age"
        if (days = tryparse(Int, value)) |> !isnothing
            modify_inventory() do
                INVENTORY.config.max_age = days
            end
        else
            printstyled(" ! ", color=:red, bold=true)
            println("must be a integer")
            return
        end
    else
        printstyled(" ! ", color=:red, bold=true)
        println("unrecognised parameter: $param")
        return
    end
    printstyled(" ✓ Done\n", color=:green)
end

function repl_config_reset(input::AbstractString)
    if input == "max_age"
        modify_inventory() do
            INVENTORY.config.max_age = DEFAULT_INVENTORY_CONFIG.max_age
        end
        printstyled(" ✓ ", color=:green)
        println("Set to $(DEFAULT_INVENTORY_CONFIG.max_age) days")
    else
        printstyled(" ! ", color=:red, bold=true)
        println("unrecognised parameter: $input")
        return
    end
end

allcompletions(::ReplCmd{:store_config_set}) = ["max_age"]
allcompletions(::ReplCmd{:store_config_reset}) = ["max_age"]

const STORE_SUBCMDS =
    ReplCmd[
        ReplCmd{:store_gc}(
            "gc", "Garbage Collect",
            _ -> garbage_collect!(INVENTORY)),
        ReplCmd{:store_stats}(
            "stats", "Statistics about the data store",
            _ -> println(" TODO")),
        ReplCmd{:store_config}(
            "config", "Manage configuration",
            ReplCmd[
                ReplCmd{:store_config_get}(
                    "get", "Get the current configuration",
                    repl_config_get),
                ReplCmd{:store_config_set}(
                    "set", "Set a configuration parameter",
                    repl_config_set),
                ReplCmd{:store_config_reset}(
                    "reset", "Set a configuration parameter",
                    repl_config_reset)])
    ]

const STORE_REPL_CMD =
    ReplCmd(:store,
            "Manipulate the data store",
            STORE_SUBCMDS)
