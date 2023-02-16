"""
    config_segments(input::AbstractString)
Parse a string representation of a TOML-style dotted path into path segments,
and any remaining content.
"""
function config_segments(input::AbstractString)
    segments = String[]
    rest = '.' * input
    while !isempty(rest) && first(rest) == '.'
        seg, rest = peelword(rest[2:end], allowdot=false)
        !isempty(seg) && push!(segments, String(seg))
    end
    segments, strip(rest)
end

"""
    config_get(input::AbstractString)
Parse and call the repl-format config getter command `input`.
"""
function config_get(input::AbstractString)
    segments, rest = config_segments(input)
    if !isempty(rest)
        printstyled(" ! ", color=:yellow, bold=true)
        println("Trailing garbage ignored in get command: \"$rest\"")
    end
    value = DataToolkitBase.config_get(segments)
    if value isa Dict && isempty(value)
        printstyled(" empty\n", color=:light_black)
    elseif value isa Dict
        TOML.print(value)
    else
        value
    end
end

"""
    config_set(input::AbstractString)
Parse and call the repl-format config setter command `input`.
"""
function config_set(input::AbstractString)
    segments, rest = config_segments(input)
    if isempty(rest)
        printstyled(" ! ", color=:red, bold=true)
        println("Value missing")
    else
        if isnothing(match(r"^true|false|[.\d]+|\".*\"|\[.*\]|\{.*\}$", rest))
            rest = string('"', rest, '"')
        end
        value = TOML.parse(string("value = ", rest))
        DataToolkitBase.config_set!(segments, value["value"])
    end
end

"""
    config_unset(input::AbstractString)
Parse and call the repl-format config un-setter command `input`.
"""
function config_unset(input::AbstractString)
    segments, rest = config_segments(input)
    if !isempty(rest)
        printstyled(" ! ", color=:yellow, bold=true)
        println("Trailing garbage ignored in unset command: \"$rest\"")
    end
    DataToolkitBase.config_unset!(segments)
end

const CONFIG_SUBCOMMANDS = ReplCmd[
    ReplCmd{:config_get}(
        "get", "Get the current configuration

The parameter to get the configuration of should be given using TOML-style dot
seperation.

Examples:
  get defaults.memorise
  get loadcache.path
  get my.\"special thing\".extra", config_get),
    ReplCmd{:config_set}(
        "set", "Set a configuration property

The parameter to set the configuration of should be given using TOML-style dot
seperation.

Similarly, the new value should be expressed using TOML syntax.

Examples:
  set defaults.memorise true
  set loadcache.path \"data/loadcache\"
  set my.\"special thing\".extra {a=1, b=2}", config_set),
    ReplCmd{:config_unset}(
        "unset", "Remove a configuration property

The parameter to be removed should be given using TOML-style dot seperation.

Examples:
  unset defaults.memorise
  unset loadcache.path
  unset my.\"special thing\".extra", config_unset),
]

"""
    config_complete(sofar::AbstractString; collection::DataCollection=first(STACK))
Provide completions for the existing TOML-style property path of `collections`'s
starting with `sofar`.
"""
function config_complete(sofar::AbstractString; collection::DataCollection=first(STACK))
    segments, rest = config_segments(sofar)
    if !isempty(rest) # if past path completion
        return String[]
    end
    if isempty(sofar) || last(sofar) == '.'
        push!(segments, "")
    end
    config = collection.parameters
    for segment in segments[1:end-1]
        if haskey(config, segment)
            config = config[segment]
        else
            return String[]
        end
    end
    if haskey(config, last(segments)) && config[last(segments)] isa Dict
        ('.' .* sort(keys(config[last(segments)]) |> collect, by=natkeygen),
         "", true)
    elseif config isa Dict
        options = sort(keys(config) |> collect, by=natkeygen)
        (filter(o -> startswith(o, last(segments)),
                options),
         String(last(segments)),
         !isempty(options))
    else
        String[]
    end
end

completions(::ReplCmd{:config_get}, sofar::AbstractString) =
    config_complete(sofar)

completions(::ReplCmd{:config_set}, sofar::AbstractString) =
    config_complete(sofar)

completions(::ReplCmd{:config_unset}, sofar::AbstractString) =
    config_complete(sofar)
