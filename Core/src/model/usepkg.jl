using Pkg

struct PkgRequiredRerunNeeded end

"""
    get_package(pkg::Base.PkgId)
    get_package(from::Module, name::Symbol)

Obtain a module specified by either `pkg` or identified by `name` and declared
by `from`. Should the package not be currently loaded, in Julia ≥ 1.7
DataToolkit will atempt to lazy-load the package and return its module.

Failure to either locate `name` or require `pkg` will result in an exception
being thrown.
"""
function get_package(pkg::Base.PkgId)
    if !Base.root_module_exists(pkg)
        if VERSION < v"1.7" # Before `Base.invokelatest`
            @error string(
                "The package $pkg is required for the operation of DataToolkit.\n",
                "DataToolkit can not do this for you, so please add `using $(pkg.name)`\n",
                "as appropriate then re-trying this operation.")
            throw(MissingPackage(pkg))
        end
        @info "Lazy-loading $pkg"
        try
            Base.require(pkg)
            true
        catch err
            pkgmsg = "is required but does not seem to be installed"
            err isa ArgumentError && occursin(pkgmsg, err.msg) &&
                isdefined(Pkg.REPLMode, :try_prompt_pkg_add) && isinteractive() &&
                Pkg.REPLMode.try_prompt_pkg_add([Symbol(pkg.name)])
        end || throw(MissingPackage(pkg))
        PkgRequiredRerunNeeded()
    else
        Base.root_module(pkg)
    end
end

function get_package(from::Module, name::Symbol)
    pkgid = get(get(EXTRA_PACKAGES, from, Dict()), name, nothing)
    if !isnothing(pkgid)
        get_package(pkgid)
    else
        throw(UnregisteredPackage(name, from))
    end
end

"""
    @addpkg name::Symbol uuid::String

Register the package identifed by `name` with UUID `uuid`.
This package may now be used with `@import \$name`.

All @addpkg statements should lie within a module's `__init__` function.

# Example

```
@addpkg CSV "336ed68f-0bac-5ca0-87d4-7b16caf5d00b"
```
"""
macro addpkg(name::Symbol, uuid::String)
    :(addpkg(@__MODULE__, Symbol($(String(name))), $uuid))
end

function addpkg(mod::Module, name::Symbol, uuid::Union{UUID, String})
    if !haskey(EXTRA_PACKAGES, mod)
        EXTRA_PACKAGES[mod] = Dict{Symbol, Vector{Base.PkgId}}()
    end
    EXTRA_PACKAGES[mod][name] = Base.PkgId(UUID(uuid), String(name))
end

"""
    invokepkglatest(f, args...; kwargs...)
Call `f(args...; kwargs...)` via `invokelatest`, and re-run if
PkgRequiredRerunNeeded is returned.
"""
function invokepkglatest(@nospecialize(f), @nospecialize args...; kwargs...)
    result = Base.invokelatest(f, args...; kwargs...)
    if result isa PkgRequiredRerunNeeded
        invokepkglatest(f, args...; kwargs...)
    else
        result
    end
end

# ------------
# @import
# ------------

module ImportParser

const PkgTerm = NamedTuple{(:name, :as), Tuple{Symbol, Symbol}}
const ImportTerm = NamedTuple{(:pkg, :property, :as),
                              Tuple{Symbol, Union{Symbol, Expr}, Symbol}}
const PkgList = Vector{PkgTerm}
const ImportList = Vector{ImportTerm}

struct InvalidImportForm <: Exception
    msg::String
end

Base.showerror(io::IO, err::InvalidImportForm) =
    print(io, "InvalidImportForm: ", err.msg)

"""
    addimport!(pkg::Symbol, property::Symbol,
               alias::Union{Symbol, Nothing}=nothing; imports::ImportList)
    addimport!(pkg::Union{Expr, Symbol}, property::Expr,
               alias::Union{Symbol, Nothing}=nothing; imports::ImportList)

Add the appropriate information to `import` for `property` to be loaded from `pkg`,
either by the default name, or as `alias` if specified.
"""
function addimport!(pkg::Symbol, property::Symbol,
                    alias::Union{Symbol, Nothing}=nothing;
                    imports::ImportList)
    push!(imports, (; pkg, property, as=something(alias, property)))
    something(alias, property)
end

function addimport!(pkg::Union{Expr, Symbol}, property::Expr,
                    alias::Union{Symbol, Nothing}=nothing;
                    imports::ImportList)
    if property.head == :.
        as = something(alias, last(property.args).value)
        push!(imports, (; pkg, property, as))
        as
    elseif property.head == :macrocall
        if length(property.args) == 2
            as = something(alias, first(property.args))
            push!(imports, (; pkg, property=first(property.args), as))
            as
        else
            throw(InvalidImportForm("invalid macro import from $pkg: $property"))
        end
    else
        throw(InvalidImportForm("$property is not valid property of $pkg"))
    end
end

"""
    addpkg!(name::Union{Expr, Symbol}, alias::Union{Symbol, Nothing}=nothing;
            pkgs::PkgList, imports::ImportList)

Add the appropriate information to `pkgs` and perhaps `imports` for the package
`name` to be loaded, either using the default name, or as `alias` if provided.
"""
function addpkg!(name::Symbol, alias::Union{Symbol, Nothing}=nothing;
                 pkgs::PkgList, imports::ImportList)
    push!(pkgs, (; name, as=something(alias, name)))
    something(alias, name)
end

function addpkg!(name::Expr, alias::Union{Symbol, Nothing}=nothing;
                 pkgs::PkgList, imports::ImportList)
    rootpkg(s::Symbol) = s
    rootpkg(e::Expr) = rootpkg(first(e.args))
    if name.head == :.
        # `name` (e.g. `Pkg.a.b.c`) is of the structure:
        # `E.(E.(E.(Symbol(:Pkg), Q(:a)), Q(:b)), Q(:c))`
        # where `E.(x, y)` is shorthand for `Expr(:., x, y)`,
        # and `Q(x)` is shorthand for `QuoteNode(x)`.
        pkgas = if (pkgindex = findfirst(p -> p.name == rootpkg(name), pkgs)) |> !isnothing
            pkgs[pkgindex].as
        else
            as = gensym(rootpkg(name))
            push!(pkgs, (; name=rootpkg(name), as))
            as
        end
        property = copy(name)
        _, prop = splitfirst(name)
        addimport!(pkgas, prop, alias; imports)
    else
        throw(InvalidImportForm("$name is not a valid package name"))
    end
end

"""
    splitfirst(prop::Expr)

Split an nested property expression into the first term and the remaining terms

## Example

```jldoctest; setup = :(import DataToolkitBase.ImportParser.splitfirst)
julia> splitfirst(:(a.b.c.d))
(:a, :(b.c.d))
```
"""
function splitfirst(prop::Expr)
    function splitfirst!(ex::Expr)
        if ex.head != :.
            throw(ArgumentError("Expected a property node, not $ex"))
        elseif ex.args[1] isa Expr && ex.args[1].args[1] isa Symbol
            leaf = ex.args[1]
            first, second = leaf.args[1], leaf.args[2].value
            ex.args[1] = second
            first
        elseif ex.args[1] isa Expr
            splitfirst!(ex.args[1])
        end
    end
    if prop.head != :.
        throw(ArgumentError("Expected a property node, not $prop"))
    elseif prop.args[1] isa Symbol
        prop.args[1], prop.args[2].value
    else
        prop_copy = copy(prop)
        splitfirst!(prop_copy), prop_copy
    end
end

"""
    propertylist(prop::Expr)

Represent a nested property expression as a vector of symbols.

## Example

```jldoctest; setup = :(import DataToolkitBase.ImportParser.propertylist)
julia> propertylist(:(a.b.c.d))
4-element Vector{Symbol}:
 :a
 :b
 :c
 :d
```
"""
function propertylist(prop::Expr)
    properties = Vector{Symbol}()
    while prop isa Expr
        prop, peel = prop.args[1], prop.args[2].value
        push!(properties, peel)
    end
    push!(properties, prop)
    reverse(properties)
end

"""
    graft(parent::Symbol, child::Union{Expr, Symbol})

Return a "grafted" expression takes the `child` property of `parent`.

## Example
```jldoctest; setup = :(import DataToolkitBase.ImportParser.graft)
julia> graft(:a, :(b.c.d))
:(a.b.c.d)

julia> graft(:a, :b)
:(a.b)
```
"""
function graft(parent::Symbol, child::Expr)
    properties = propertylist(child)
    gexpr = Expr(:., parent, QuoteNode(popfirst!(properties)))
    while !isempty(properties)
        gexpr = Expr(:., gexpr, QuoteNode(popfirst!(properties)))
    end
    gexpr
end

graft(parent::Symbol, child::Symbol) =
    Expr(:., parent, QuoteNode(child))

"""
    flattenterms(terms)

Where `terms` is a set of terms produced from parsing an expression like
`foo as bar, baz`, flatten out the individual tokens.

## Example

```jldoctest; setup = :(import DataToolkitBase.ImportParser.flattenterms)
julia> flattenterms((:(foo.bar), :as, :((bar, baz, baz.foo, other.thing)), :as, :((other, more))))
9-element Vector{Union{Expr, Symbol}}:
 :(foo.bar)
 :as
 :bar
 :baz
 :(baz.foo)
 :(other.thing)
 :as
 :other
 :more
```
"""
function flattenterms(terms)
    stack = Vector{Union{Symbol, Expr}}()
    for term in terms
        if term isa Symbol || term.head == :.
            push!(stack, term)
        elseif term isa Expr && term.head == :tuple
            append!(stack, term.args)
        end
    end
    stack
end

"""
    extractterms(terms)

Convert an import expression (`terms`), to a named tuple giving a `PkgList` (as
`pkgs`) and `ImportList` (as `imports`).
"""
function extractterms(@nospecialize(terms))
    pkgs = PkgList()
    imports = ImportList()
    if length(terms) == 1 && (terms[1] isa Symbol || terms[1].head == :.)
        # Case 1: @import Pkg(.thing)?
        addpkg!(first(terms); pkgs, imports)
    elseif terms[1] isa Expr &&
        ((terms[1].head == :call && terms[1].args[1] == :(:)) ||
        (terms[1].head == :tuple && terms[1].args[1] isa Expr &&
        terms[1].args[1].head == :call && terms[1].args[1].args[1] == :(:)))
        # Case 2: @import pkg: a, b as c, d, e, f as g, h, ...
        stack = Union{Symbol, Expr}[]
        pkg = if terms[1].head == :call
            append!(stack, terms[1].args[3:end])
            terms[1].args[2]
        else
            push!(stack, terms[1].args[1].args[3])
            append!(stack, terms[1].args[2:end])
            terms[1].args[1].args[2]
        end
        pkgalias = gensym(if pkg isa Symbol pkg else last(pkg.args).value end)
        addpkg!(pkg, pkgalias; pkgs, imports)
        append!(stack, flattenterms(terms[2:end]))
        while !isempty(stack)
            if length(stack) > 2 && stack[2] == :as
                addimport!(pkgalias, stack[1], stack[3]; imports)
                deleteat!(stack, 1:3)
            else
                addimport!(pkgalias, stack[1]; imports)
                deleteat!(stack, 1)
            end
        end
    elseif length(terms) == 1 && terms[1] isa Expr && terms[1].head == :tuple
        # Case 3: @import Pkg1, Pkg2(.thing)?, ...
        for term in terms[1].args
            addpkg!(term; pkgs, imports)
        end
    else
        # Case: @import pkg1 as pkg2, pkg3, ...
        stack = flattenterms(terms)
        while !isempty(stack)
            if length(stack) > 2 && stack[2] == :as
                addpkg!(stack[1], stack[3]; pkgs, imports)
                deleteat!(stack, 1:3)
            else
                addpkg!(stack[1]; pkgs, imports)
                deleteat!(stack, 1)
            end
        end
    end
    (; pkgs, imports)
end

"""
    genloadstatement(pkgs::PkgList, imports::ImportList)

Create an `Expr` that sets up `pkgs` and `imports`.
"""
function genloadstatement(pkgs::PkgList, imports::ImportList)
    Expr(:block,
         Iterators.flatten(
             map(pkgs) do (; name, as)
                 (Expr(:(=), as,
                       Expr(:call,
                            GlobalRef(parentmodule(@__MODULE__), :get_package),
                            :(@__MODULE__),
                            QuoteNode(name))),
                  Expr(:||,
                       Expr(:call, :isa, as, GlobalRef(Core, :Module)),
                       Expr(:return, as)))
         end)...,
         map(imports) do (; pkg, property, as)
             if property isa Symbol
                 Expr(:(=), as, Expr(:., pkg, QuoteNode(property)))
             elseif property isa Expr
                 Expr(:(=), as, graft(pkg, property))
             end
         end...)
end

"""
    @import pkg1, pkg2...
    @import pkg1 as name1, pkg2 as name2...
    @import pkg: foo, bar...
    @import pkg: foo as bar, bar as baz...

Fetch modules previously registered with `@addpkg`, and import them into the
current namespace. This macro tries to largely mirror the syntax of `using`.

If a required package had to be loaded for the `@import` statement, a
`PkgRequiredRerunNeeded` singleton will be returned.

# Example

```julia
@import pkg
pkg.dothing(...)
# Alternative form
@import pkg: dothing
dothing(...)
```
"""
macro localimport(terms::Union{Expr, Symbol}...)
    (; pkgs, imports) = extractterms(terms)
    genloadstatement(pkgs, imports) |> esc
end

end

using .ImportParser

# To get around ERROR: syntax: invalid name "import"
const var"@import" = ImportParser.var"@localimport"
