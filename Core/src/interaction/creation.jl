# For programmatic creation of DataCollection elements

DataCollection(name::Union{String, Nothing}=nothing, config::Dict{String, <:Any} = Dict{String, Any}();
               path::Union{String, Nothing}=nothing) =
    DataCollection(LATEST_DATA_CONFIG_VERSION, name, uuid4(), String[],
                   Dict{String, Any}(config), DataSet[], path,
                   AdviceAmalgamation(String[]), Main)

# DataSet creation

function create(parent::DataCollection, ::Type{DataSet}, name::AbstractString, spec::Dict{String, <:Any})
    if !haskey(spec, "uuid")
        spec = merge(spec, Dict("uuid" => uuid4()))
    end
    uuid = if haskey(spec, "uuid") UUID(spec["uuid"]) else uuid4() end
    dataset = @advise fromspec(DataSet, parent, String(name), Dict{String, Any}(spec))
end

function create!(parent::DataCollection, ::Type{DataSet}, name::AbstractString, spec::Dict{String, <:Any})
    dataset = create(parent, DataSet, name, spec)
    push!(parent.datasets, dataset)
    dataset
end

create!(parent::DataCollection, ::Type{DataSet}, name::AbstractString, specs::Pair{String, <:Any}...) =
    create!(parent, DataSet, name, Dict{String, Any}(specs))

function dataset!(collection::DataCollection, name::String, parameters::Dict{String, <:Any})
    dataset = DataSet(collection, name, uuid4(),
                      Dict{String, Any}(parameters),
                      DataStorage[], DataLoader[], DataWriter[])
    push!(collection.datasets, dataset)
    dataset
end

dataset!(collection::DataCollection, name::String, parameters::Pair{String, <:Any}...) =
    dataset!(collection, name, Dict{String, Any}(parameters))

# Transformer creation (pure)

function create(parent::DataSet, T::Type{<:DataTransformer}, spec::Dict{String, <:Any})
    T <: DataStorage || T <: DataLoader || T <: DataWriter ||
        throw(ArgumentError("Unknown transformer type: $T"))
    tdriver(::Type{<:DataTransformer}) = nothing
    tdriver(::Type{<:DataTransformer{_kind, D}}) where {_kind, D} = D
    if !haskey(spec, "driver")
        driver = tdriver(T)
        if !isnothing(driver)
            spec = merge(spec, Dict("driver" => String(driver)))
        end
    end
    if haskey(spec, "type") && typeof(spec["type"]) == QualifiedType
        spec = merge(spec, Dict{String, Any}("type" => string(spec["type"])))
    elseif haskey(spec, "type") && typeof(spec["type"]) == Vector{QualifiedType}
        spec = merge(spec, Dict{String, Any}("type" => map(string, spec["type"])))
    end
    @advise fromspec(T, parent, Dict{String, Any}(spec))
end

create(parent::DataSet, T::Type{<:DataTransformer}, driver::Symbol, spec::Dict{String, <:Any} = Dict{String, Any}()) =
    create(parent, T, merge(spec, Dict("driver" => String(driver))))

create(parent::DataSet, T::Type{<:DataTransformer}, driver::Symbol, specs::Pair{String, <:Any}...) =
    create(parent, T, driver, Dict{String, Any}(specs))

# Transformer creation (modifying)

function create!(parent::DataSet, T::Type{<:DataTransformer}, spec::Dict{String, <:Any})
    dslist = if T <: DataStorage
        parent.storage
    elseif T <: DataLoader
        parent.loaders
    elseif T <: DataWriter
        parent.writers
    else
        throw(ArgumentError("Unknown transformer type: $T"))
    end
    transformer = create(parent, T, spec)
    push!(dslist, transformer)
    transformer
end

create!(parent::DataSet, T::Type{<:DataTransformer}, driver::Symbol, spec::Dict{String, <:Any} = Dict{String, Any}()) =
    create!(parent, T, merge(spec, Dict("driver" => String(driver))))

create!(parent::DataSet, T::Type{<:DataTransformer{_kind, D}}, spec::Dict{String, <:Any} = Dict{String, Any}()) where {_kind, D} =
    create!(parent, T, D, spec)

create!(parent::DataSet, T::Type{<:DataTransformer{_kind, D}}, driver::Symbol, specs::Pair{String, <:Any}...) where {_kind, D} =
    create!(parent, T, D, driver, Dict{String, Any}(specs))

# Dedicated storage/loader/writer creation (modifying)

storage!(dataset::DataSet, driver::Symbol, parameters::Dict{String, <:Any}) =
    create!(dataset, DataStorage, driver, parameters)

loader!(dataset::DataSet, driver::Symbol, parameters::Dict{String, <:Any}) =
    create!(dataset, DataLoader, driver, parameters)

writer!(dataset::DataSet, driver::Symbol, parameters::Dict{String, <:Any}) =
    create!(dataset, DataWriter, driver, parameters)

storage!(dataset::DataSet, driver::Symbol, parameters::Pair{String, <:Any}...) =
    storage!(dataset, driver, Dict{String, Any}(parameters))

loader!(dataset::DataSet, driver::Symbol, parameters::Pair{String, <:Any}...) =
    loader!(dataset, driver, Dict{String, Any}(parameters))

writer!(dataset::DataSet, driver::Symbol, parameters::Pair{String, <:Any}...) =
    writer!(dataset, driver, Dict{String, Any}(parameters))

# Interactive/specialised transformer creation

"""
    trycreateauto(parent::DataSet, T::Type{<:DataTransformer{_kind, driver}}, arg::String; interactive::Bool=isinteractive())

Attempts to create a data transformer of type `T` associated with the `parent`
dataset using the specified `arg`. The function can operate in both interactive
and non-interactive modes, depending on the value of the `interactive` flag.

If `interactive` is set to `true`, the function first attempts to create the
transformer interactively using `createinteractive`. This involves prompting the
user for additional input if needed. If the interactive creation is successful
and returns a valid specification, it is used to instantiate the transformer.

If `interactive` is `false`, or if `createinteractive` returns `nothing`, the
function proceeds to attempt an automatic creation using `createauto`. This
method attempts to create the transformer without user input. If `createauto`
returns a valid specification, the transformer is created accordingly.

The function returns the created transformer if successful, or `nothing` if the
creation process fails in both interactive and non-interactive modes.
"""
function trycreateauto(parent::DataSet, T::Type{<:DataTransformer{_kind, driver}}, arg::String;
                       interactive::Bool=isinteractive()) where {_kind, driver}
    @nospecialize
    if interactive
        paramspec = createinteractive(parent, T, arg)
        if paramspec === true
            spec = Dict{String, Any}()
        end
        if paramspec ∉ (false, nothing)
            prefix = " $(string(nameof(T))[5])($driver) "
            spec = interactiveparams(paramspec, prefix)
            return create(parent, T, Dict{String, Any}(spec))
        end
    end
    spec = createauto(parent, T, arg)::Union{Dict{String, <:Any}, Bool, Nothing}
    spec ∈ (false, nothing) && return
    if spec === true
        spec = Dict{String, Any}()
    end
    create(parent, T, Dict{String, Any}(spec))
end

"""
    trycreateauto(parent::DataSet, T::Type{<:DataTransformer}, driver::Symbol, source::String;
                minpriority::Int=-100, maxpriority::Int=100, interactive::Bool=isinteractive())

Attempt to create a new `T` with driver `driver` from `parent`.

If `driver` is the symbol `*` then all possible drivers are checked and the
highest priority (according to `createpriority`) valid driver used. Drivers with
a priority outside `minpriority`–`maxpriority` will not be considered.

The created data transformer is returned, unless the given `driver` is not
valid, in which case `nothing` is returned instead.
"""
function trycreateauto(parent::DataSet, T::Type{<:DataTransformer}, driver::Symbol, source::String;
                       minpriority::Int=-100, maxpriority::Int=100, interactive::Bool=isinteractive())
    @nospecialize
    if driver !== :*
        return trycreateauto(parent, T{driver}, source)
    end
    relevant_methods = if T == DataStorage
        vcat(methods(storage), methods(getstorage))
    elseif T == DataLoader
        methods(load)
    elseif T == DataWriter
        methods(save)
    end
    alldrivers = Symbol[]
    for m in relevant_methods
        arg1 = Base.unwrap_unionall(Base.unwrap_unionall(m.sig).types[2])
        if arg1 isa DataType && first(arg1.parameters) isa Symbol &&
            minpriority <= createpriority(T{arg1}) <= maxpriority
            push!(alldrivers, first(arg1.parameters))
        end
    end
    sort!(alldrivers, by = drv -> createpriority(T{drv}))
    for drv in alldrivers
        transformer = trycreateauto(parent, T{drv}, source)
        !isnothing(transformer) && return transformer
    end
end

"""
    createinteractive([dataset::DataSet], T::Type{<:DataTransformer}, source::String)

Attempts to create a data transformer of type `T` with user interaction, using
`source` and `dataset`. Prompts the user for additional information if required.
Returns either a specification for the transformer as a dictionary, `true` to
indicate that an empty (no parameters) transformer should be created, or
`nothing` if the transformer cannot be created interactively.

Specific transformers should implement specialised forms of this function,
either returning `nothing` if creation is not applicable, or a "create spec
form" as a list of `key::String => value` pairs. For example:

["foo" => "bar",
 "baz" => 2]

In addition to accepting TOML-representable values, a `NamedTuple` can be used
to define the interactive prompt with fields like:

(; prompt::String = "\$key",
   type::Type{String or Bool or <:Number} = String,
   default::type = false or "",
   optional::Bool = false,
   skipvalue::Any = nothing,
   post::Function = identity)

The function can also accept a `Function` that takes the current specification
as an argument and returns a TOML-representable value or `NamedTuple`.

Use this function when user interaction is necessary for the creation process.
For cases where the creation can be handled programmatically without user input,
consider using `createauto`.
"""
function createinteractive end

createinteractive(::DataSet, T::Type{<:DataTransformer}, arg::String) =
    createinteractive(T, arg)
createinteractive(::Type{<:DataTransformer}, ::String) = nothing

"""
    interactiveparams(spec::Vector, prefix::AbstractString = " ")

Interactively prompt the user for parameters based on the specification `spec`,
using `prefix` as the prompt prefix. Returns a dictionary of the parameters
entered by the user, or `nothing`.

Display backends are searched in the order of `Base.Multimedia.displays`, and
can declare support by implementing

    interactiveparams(display, spec::Vector, prefix::AbstractString)
"""
function interactiveparams(spec::Vector, prefix::AbstractString = " ")
    for display in Base.Multimedia.displays
        filled = interactiveparams(display, spec, prefix)
        !isnothing(filled) && return filled
    end
end

interactiveparams(_display::Any, _spec::Vector, _promptprefix::AbstractString) =
    nothing

"""
    createauto([dataset::DataSet], T::Type{<:DataTransformer}, source::String)

Automatically attempts to create a data transformer of type `T` using `source`
and optionally `dataset`, without requiring user interaction. Returns either a
specification for the transformer as a `Dict{String, Any}`, `true` to indicate
that an empty (no parameters) transformer should be created, or
`false`/`nothing` if the transformer cannot be created automatically.

Specific transformers should implement specialised forms of this function,
either returning `nothing` if automatic creation is not possible, or a "create
spec form" as a list of `key::String => value` pairs. For example:

```
["foo" => "bar",
 "baz" => 2]
```

Use this function when the creation process should be handled programmatically
without user input. If user interaction is required to gather additional
information use `createinteractive`.
"""
function createauto end

createauto(::DataSet, T::Type{<:DataTransformer}, arg::String) =
    createauto(T, arg)
createauto(::Type{<:DataTransformer}, ::Any) = nothing

# `createpriority` isn't actually used anywhere in DTkCore,
# but it needs to be defined somewhere fairly central to
# make it easy to be extended and used across packages.
"""
    createpriority(T::Type{<:DataTransformer})

The priority with which a transformer of type `T` should be created.
This can be any integer, but try to keep to -100–100 (see `create`).
"""
createpriority(T::Type{<:DataTransformer}) = 0
