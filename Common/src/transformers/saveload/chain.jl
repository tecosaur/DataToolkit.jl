# Example:
#---
# [data.loader]
# driver = "chain"
# type = ["DataFrames.DataFrame"] # final supported data
# loaders = [
#   { driver = "gzip", type = "IO" },
#   { driver = "csv", type = "DataFrames.DataFrame"}
# ]
# # alternative
# loaders = [ "gzip", "csv" ]

function load(loader::DataLoader{:chain}, from::Any, ::Type{T}) where {T}
    subloaders = map(spec -> DataLoader(loader.dataset, spec),
                     @getparam(loader."loaders"::Vector, Dict{String, Any}[]))
    types = loadtypepath(subloaders, typeof(from), T)
    if !isnothing(types)
        reduce((value, (subloader, as)) ->
            DataToolkitBase.invokepkglatest(load, subloader, value, as),
               zip(subloaders, types), init=from)::Union{T, Nothing}
    end
end

supportedtypes(::Type{DataLoader{:chain}}, spec::Dict{String, Any}) =
    let lastloader = last(@getparam spec."loaders"::Vector [nothing])
        if lastloader isa Dict # { driver="X", ... } form
            explicit_type = @getparam lastloader."type"
            if explicit_type isa String
                [parse(QualifiedType, explicit_type)]
            elseif explicit_type isa Vector
                parse.(QualifiedType, explicit_type)
            else
                supportedtypes(DataLoader{Symbol(lastloader["driver"])}, lastloader)
            end
        elseif lastloader isa String # "X" shorthand form
            supportedtypes(DataLoader{Symbol(lastloader)})
        else
            QualifiedType[]
        end
    end

"""
    loadtypepath(subloaders::Vector{DataLoader}, targettype::Type)
Return the sequence of types that the `subloaders` must be asked for to finally
produce `targettype` from an initial `fromtype`. If this is not possible,
`nothing` is returned instead.
"""
function loadtypepath(subloaders::Vector{DataLoader}, fromtype::Type, targettype::Type)
    toploader = last(subloaders)
    loadertypes = filter(!isnothing, typeify.(toploader.type))
    if length(subloaders) > 1
        midtypes = if toploader isa DataLoader{:julia}
            # Julia loaders are a bit special, as they have parameter
            # (`input`) which if set indicates the type expected in the
            # argument to the Julia function. If not set, then this is
            # a keyword-argument only Julia loader, and so it expects
            # Nothing. Really though, only the input variety of loaders
            # makes sense in a chain loader. We may as well be
            # exhaustive though.
            if isempty(@getparam toploader."input"::String "")
                [Nothing]
            else
                iqtype = QualifiedType(get(toploader, "input"))
                itype = @something typeify(iqtype) try
                    # It may be the case that the loader requires a lazy loaded
                    # package, in this case it may be a good idea to just /try/
                    # requiring it and seeing what happens.
                    pkg = DataToolkitBase.get_package(
                        toploader.dataset.collection.mod,
                        iqtype.root)
                    if pkg isa DataToolkitBase.PkgRequiredRerunNeeded
                        typeify(iqtype)
                    else
                        # If no rerun is raised, then then the package is
                        # already loaded and the unresolvable type will still be
                        # unresolvable, so return nothing.
                        Some(nothing)
                    end
                catch e
                    if e isa ArgumentError
                        Some(nothing)
                    else
                        rethrow()
                    end
                end
                if !isnothing(itype)
                    [itype]
                else
                    Type[]
                end
            end
        else
            potentialmethods =
                [methods(load, Tuple{typeof(toploader), Any, Type{suptype}}).ms
                for suptype in loadertypes
                    if suptype <: targettype] |> Iterators.flatten |> unique
            [m.sig.types[3] for m in potentialmethods]
        end
        subpaths = filter(!isnothing,
                          [loadtypepath(subloaders[1:end-1], fromtype, midtype)
                           for midtype in midtypes])
        if !isempty(subpaths)
            vcat(first(subpaths), targettype)
        end
    else
        ms = methods(load, Tuple{typeof(toploader), fromtype, Type{targettype}})
        if !isempty(ms)
            targettype
        end
    end
end

createpriority(::Type{DataLoader{:chain}}) = 5

function create(::Type{DataLoader{:chain}}, source::String, dataset::DataSet)
    # Prompted by compressed file types, e.g. ".csv.gz"
    if !isnothing(match(r"\.\w+\.\w+$", source)) && isnothing(match(r"\.git$", source))
        base, inner, outer = match(r"^(.*)\.(\w+)\.(\w+)$", source).captures
        outerloader = create(DataLoader, :*, source, dataset;
                             minpriority=1+createpriority(DataLoader{:chain}))
        if !isnothing(outerloader)
            innerloader = create(DataLoader, :*, "$base.$inner", dataset)
            if !isnothing(innerloader)
                minimalspec(template) = Dict{String, Any}(
                    "driver" => template["driver"])
                ospec = DataToolkitBase.@advise dataset tospec(outerloader)
                ispec = DataToolkitBase.@advise dataset tospec(innerloader)
                ["loaders" =>
                    if ospec == minimalspec(ospec) && ispec == minimalspec(ispec)
                        [ospec["driver"], ispec["driver"]]
                    else
                        [ospec, ispec]
                    end]
            end
        end
    end
end

const CHAIN_DOC = md"""
Chain multiple transformers together

# Input/Output

The `chain` loader can accept any form of input, and produce any form of output.

In passes the initial input through a *chain* of other loaders, via the `loader`
property. A list of loader driver names can be given to chain together those
loaders with no properties. To provide properties, use a TOML array of tables
and specify the full (`driver = "name", ...`) form.

Writing is not currently supported.

# Usage examples

```toml
[[iris.loader]]
driver = "chain"
loaders = ["gzip", "csv"]
```

```toml
[[iris.loader]]
driver = "chain"
loaders = ["gzip", { driver = "tar", file = "iris.csv" }, "csv"]
```

```toml
[[chained.loader]]
driver = "chain"

    [[chained.loader.loaders]]
    driver = "gzip"

    [[chained.loader.loaders]]
    driver = "csv"

    [[chained.loader.loaders]]
    driver = "julia"
    input = "DataFrame"
    path = "scripts/custom_postprocessing.jl"
    type = "DataFrame"
```
"""
