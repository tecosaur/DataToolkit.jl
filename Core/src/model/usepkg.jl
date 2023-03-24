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
            throw(ErrorException("Missing package: $pkg"))
        else
            @info "Lazy-loading $pkg"
        end
        try
            Base.require(pkg)
        catch err
            pkgmsg = "is required but does not seem to be installed"
            if err isa ArgumentError && occursin(pkgmsg, err.msg) &&
                isdefined(Pkg.REPLMode, :try_prompt_pkg_add) && isinteractive()
                Pkg.REPLMode.try_prompt_pkg_add([Symbol(pkg.name)]) ||
                    throw(ErrorException("Missing package: $pkg"))
            else
                rethrow(err)
            end
        end
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
        throw(ArgumentError("Package $name was not registered by $from, and so cannot be used by $from."))
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
    EXTRA_PACKAGES[mod][name]= Base.PkgId(UUID(uuid), String(name))
end

macro localimport(terms::Union{Expr, Symbol}...)
    pkgs = Tuple{Symbol, Symbol}[]
    imports = Tuple{Symbol, Symbol, Symbol}[]
    function flattento!(stack, terms)
        for term in terms
            if term isa Symbol
                push!(stack, term)
            elseif term isa Expr && term.head == :tuple
                append!(stack, term.args)
            end
        end
    end
    if length(terms) == 1 && terms[1] isa Symbol
        # Case: @import pkg
        push!(pkgs, (terms[1], terms[1]))
    elseif terms[1] isa Expr &&
        ((terms[1].head == :call && terms[1].args[1] == :(:)) ||
        (terms[1].head == :tuple && terms[1].args[1] isa Expr &&
        terms[1].args[1].head == :call && terms[1].args[1].args[1] == :(:)))
        # Case: @import pkg: a, b as c, d, e, f as g, h, ...
        stack = Symbol[]
        pkg = if terms[1].head == :call
            append!(stack, terms[1].args[3:end])
            terms[1].args[2]
        else
            push!(stack, terms[1].args[1].args[3])
            append!(stack, terms[1].args[2:end])
            terms[1].args[1].args[2]
        end
        push!(pkgs, (pkg, pkg))
        flattento!(stack, terms[2:end])
        while !isempty(stack)
            if length(stack) > 2 && stack[2] == :as
                push!(imports, (pkg, stack[1], stack[3]))
                deleteat!(stack, 1:3)
            else
                push!(imports, (pkg, stack[1], stack[1]))
                deleteat!(stack, 1)
            end
        end
    elseif length(terms) == 1 && terms[1] isa Expr && terms[1].head == :tuple
        # Case: @import pkg1, pkg2, pkg3, ...
        append!(pkgs, zip(terms[1].args, terms[1].args) |> collect)
    else
        # Case: @import pkg1 as pkg2, pkg3, ...
        stack = Symbol[]
        flattento!(stack, terms)
        while !isempty(stack)
            if length(stack) > 2 && stack[2] == :as
                push!(pkgs, (stack[1], stack[3]))
                deleteat!(stack, 1:3)
            else
                push!(pkgs, (stack[1], stack[1]))
                deleteat!(stack, 1)
            end
        end
    end
    Expr(:block,
         Iterators.flatten(
             map(pkgs) do (pkg, as)
                 (Expr(:(=), esc(as),
                       :($(@__MODULE__).get_package(
                           @__MODULE__, $(QuoteNode(pkg))))),
                  :($(esc(as)) isa $(esc(:Core)).Module || return $(esc(as))))
         end)...,
         map(imports) do (pkg, load, as)
             Expr(:(=), esc(as), :($(esc(pkg)).$load))
         end...)
end

# To get around ERROR: syntax: invalid name "import"
const var"@import" = var"@localimport"

@doc """
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
""" :(@import)

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
