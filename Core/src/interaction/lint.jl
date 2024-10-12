"""
Representation of a lint item.

# Constructors

```julia
LintItem(source, severity::Union{Int, Symbol}, id::Symbol, message::String,
         fixer::Union{Function, Nothing}=nothing, autoapply::Bool=false)
```

`source` is the object that the lint applies to.

`severity` should be one of the following values:
- `0` or `:debug`, for messages that may assist with debugging problems that may
  be associated with particular configuration.
- `1` or `:info`, for informational messages understandable to end-users.
- `2` or `:warning`, for potentially harmful situations.
- `3` or `:error`, for severe issues that will prevent normal functioning.

`id` is a symbol representing the type of lint (e.g. `:unknown_driver`)

`message` is a message, intelligible to the end-user, describing the particular
nature of the issue with respect to `source`. It should be as specific as possible.

`fixer` can be set to a function which modifies `source` to resolve the issue.
If `autoapply` is set to `true` then `fixer` will be called spontaneously.
The function should return `true` or `false` to indicate whether it was able
to successfully fix the issue.

As a general rule, fixers that do or might require user input should *not* be
run automatically, and fixers that can run without any user input and
always "do the right thing" should be run automatically.

# Examples

TODO

# Structure

```julia
struct LintItem{S}
    source    ::S
    severity  ::UInt8
    id        ::Symbol
    message   ::String
    fixer     ::Union{Function, Nothing}
    autoapply ::Bool
end
```
"""
struct LintItem{S}
    source::S
    severity::UInt8
    id::Symbol
    message::String
    fixer::Union{Function, Nothing}
    autoapply::Bool
end

LintItem(source, severity::Symbol, id::Symbol, message::String,
         fixer::Union{Function, Nothing}=nothing, autoapply::Bool=false) =
             LintItem(source, LINT_SEVERITY_MAPPING[severity], id,
                      message, fixer, autoapply)

"""
    lint(obj::T)

Call all of the relevant linter functions on `obj`. More specifically,
the method table is searched for `lint(obj::T, ::Val{:linter_id})` methods
(where `:linter_id` is a stand-in for the actual IDs used), and each specific
lint function is invoked and the results combined.

!!! note
    Each specific linter function should return a vector of relevant
    [`LintItem`](@ref)s, i.e.
    ```julia
    lint(obj::T, ::Val{:linter_id}) -> Union{Vector{LintItem{T}}, LintItem{T}, Nothing}
    ```
    See the documentation on [`LintItem`](@ref) for more information on how it should be
    constructed.
"""
function lint(obj::T) where {T <: Union{DataCollection, DataSet, <:DataTransformer}}
    linters = methods(lint, Tuple{T, Val}).ms
    @advise lint(obj, linters)
end

function lint(obj::T, linters::Vector{Method}) where {T}
    lintiter(l::Vector{LintItem}) = l
    lintiter(l::LintItem) = (l,)
    lintiter(::Nothing) = ()
    issues = Iterators.map(linters) do linter
        func = first(linter.sig.parameters).instance
        val = last(linter.sig.parameters)
        invoke(func, Tuple{T, val}, obj, val()) |> lintiter
    end |> Iterators.flatten |> collect
    sort(issues, by=i -> i.severity)
end

"""
    LintReport

A collection of [`LintItem`](@ref)s that apply to a particular
[`DataCollection`](@ref).

Depending on the constructor called, the report may be for the entire collection
or just a single [`DataSet`](@ref).

# Constructors

    LintReport(collection::DataCollection) -> LintReport
    LintReport(dataset::DataSet) -> LintReport
"""
struct LintReport
    collection::DataCollection
    results::Vector{LintItem}
    partial::Bool
end

function LintReport(collection::DataCollection)
    results = Vector{Vector{LintItem}}()
    push!(results, lint(collection))
    for dataset in collection.datasets
        push!(results, lint(dataset))
        for dtfield in (:storage, :loaders, :writers)
            for dt in getfield(dataset, dtfield)
                push!(results, lint(dt))
            end
        end
    end
    LintReport(collection, Vector{LintItem}(Iterators.flatten(results) |> collect), false)
end

function LintReport(dataset::DataSet)
    results = Vector{Vector{LintItem}}()
    push!(results, lint(dataset))
    for dtfield in (:storage, :loaders, :writers)
        for dt in getfield(dataset, dtfield)
            push!(results, lint(dt))
        end
    end
    LintReport(dataset.collection,
               Vector{LintItem}(Iterators.flatten(results) |> collect),
               true)
end

function Base.show(io::IO, report::LintReport)
    printstyled(io, ifelse(report.partial, "Partial lint results for '", "Lint results for '"),
                report.collection.name, "' collection",
                color=:blue, bold=true)
    printstyled(io, " ", report.collection.uuid, color=:light_black)
    if isempty(report.results)
        printstyled("\n ✓ No issues found", color=:green)
    end
    lastsource::Any = nothing
    objinfo(::DataCollection) = nothing
    function objinfo(d::DataSet)
        printstyled(io, "\n• ", d.name, color=:blue, bold=true)
        printstyled(io, " ", d.uuid, color=:light_black)
    end
    function objinfo(a::A) where {A <: DataTransformer}
        if lastsource isa DataSet
            lastsource == a.dataset
        elseif lastsource isa DataTransformer
            lastsource.dataset == a.dataset
        else
            false
        end || objinfo(a.dataset)
        printstyled("\n  ‣ ", first(A.parameters), ' ',
                    join(lowercase.(split(string(nameof(A)), r"(?=[A-Z])")), ' '),
                    color=:blue, bold=true)
    end
    indentlevel(::DataCollection) = 0
    indentlevel(::DataSet) = 2
    indentlevel(::DataTransformer) = 4
    for (i, lintitem) in enumerate(report.results)
        if lintitem.source !== lastsource
            objinfo(lintitem.source)
            lastsource = lintitem.source
        end
        let (color, label) = LINT_SEVERITY_MESSAGES[lintitem.severity]
            printstyled(io, '\n', ' '^indentlevel(lintitem.source), label,
                        '[', i, ']', ':'; color)
        end
        first, rest... = split(lintitem.message, '\n')
        print(io, ' ', first)
        for line in rest
            print(io, '\n', ' '^indentlevel(lintitem.source), line)
        end
    end
    if length(report.results) > 12
        print("\n\n")
        printstyled(length(report.results), color=:light_white),
        print(" issues identified:")
        for category in (:error, :warning, :suggestion, :info, :debug)
            catcode = LINT_SEVERITY_MAPPING[category]
            ncat = sum(r -> r.severity == catcode, report.results)
            if ncat > 0
                printstyled("\n  • ", color=:blue)
                printstyled(ncat, color=:light_white)
                printstyled(category, ifelse(ncat == 1, "", "s"),
                            color=LINT_SEVERITY_MESSAGES[catcode])
            end
        end
    end
end

"""
    lintfix(report::LintReport)

Attempt to fix as many issues raised in `report` as possible.
"""
function lintfix(report::LintReport, manualfix::Bool=false)
    autofixed = Vector{Tuple{Int, LintItem, Bool}}()
    fixprompt = Vector{Tuple{Int, LintItem}}()
    # Auto-apply fixes
    for (i, lintitem) in enumerate(report.results)
        isnothing(lintitem.fixer) && continue
        if lintitem.autoapply
            push!(autofixed, (i, lintitem, lintitem.fixer(lintitem)))
        else
            push!(fixprompt, (i, lintitem))
        end
    end
    if !isempty(autofixed)
        print("Automatically fixed ")
        printstyled(sum(last.(autofixed)), color=:light_white)
        print(ifelse(sum(last.(autofixed)) == 1, " issue: ", " issues: "))
        for fixresult in filter(last, autofixed)
            i, lintitem, _ = fixresult
            printstyled(i, color=first(LINT_SEVERITY_MESSAGES[lintitem.severity]))
            fixresult === last(autofixed) || print(", ")
        end
        print(".\n")
        if !all(last, autofixed)
            print("Failed to automatically fix ", sum(.!last.(autofixed)), " issues: ")
            printstyled(sum(.!last.(autofixed)), color=:light_white)
            print(ifelse(sum(.!last.(autofixed)) == 1, "issue: ", " issues: "))
            for fixresult in filter(last, autofixed)
                i, lintitem, _ = fixresult
                printstyled(i, color=first(LINT_SEVERITY_MESSAGES[lintitem.severity]))
                fixresult === last(autofixed) || print(", ")
            end
            print('\n')
        end
    end
    if !isempty(autofixed)
        write(report.collection)
    end
    # Manual fixes
    if !isempty(fixprompt) &&
        (isinteractive() || manualfix) &&
        hasmethod(linttryfix, Tuple{typeof(fixprompt)})
        linttryfix(fixprompt) && write(report.collection)
    end
    nothing
end

# Implemented in the REPL package, see `../../../REPL/ext/REPLMode/lint.jl`.
function linttryfix end
