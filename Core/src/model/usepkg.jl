struct PkgRequiredRerunNeeded end

"""
    get_package(pkg::Base.PkgId)
    get_package(from::Module, name::Symbol)

Obtain a module specified by either `pkg` or identified by `name` and declared
by `from`. Should the package not be currently loaded DataToolkit will attempt
to lazy-load the package and return its module.

Failure to either locate `name` or require `pkg` will result in an exception
being thrown.
"""
function get_package(pkg::Base.PkgId)
    if !Base.root_module_exists(pkg)
        fmtpkg = string(pkg.name, '[', pkg.uuid, ']')
        @info "Lazy-loading $fmtpkg"
        try
            Base.require(pkg)
            true
        catch err
            pkgmsg = "is required but does not seem to be installed"
            err isa ArgumentError && isinteractive() && occursin(pkgmsg, err.msg) &&
                try_install_pkg(pkg)
        end || throw(MissingPackage(pkg))
        PkgRequiredRerunNeeded()
    else
        Base.root_module(pkg)
    end
end

const PKG_ID = Base.PkgId(Base.UUID("44cfe95a-1eb2-52ea-b672-e2afdf69b78f"), "Pkg")

@static if VERSION > v"1.11-alpha1"
    function try_install_pkg(pkg::Base.PkgId)
        Pkg = try
            @something get(Base.loaded_modules, PKG_ID, nothing) Base.require(PKG_ID)
        catch _ end
        isnothing(Pkg) && return false
        repl_ext = Base.get_extension(Pkg, :REPLExt)
        !isnothing(repl_ext) &&
            isdefined(repl_ext, :try_prompt_pkg_add) &&
            Base.get_extension(Pkg, :REPLExt).try_prompt_pkg_add([Symbol(pkg.name)])
    end
else
    function try_install_pkg(pkg::Base.PkgId)
        Pkg = get(Base.loaded_modules, PKG_ID, nothing)
        !isnothing(Pkg) && isdefined(Pkg, :REPLMode) &&
            isdefined(Pkg.REPLMode, :try_prompt_pkg_add) &&
            Pkg.REPLMode.try_prompt_pkg_add([Symbol(pkg.name)])
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

Register the package identified by `name` with UUID `uuid`.
This package may now be used with `@require \$name`.

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

"""
    @require Package
    @require Package = "UUID"
"""
macro require(pkg::Symbol)
    quote
        $(esc(pkg)) = get_package($__module__, $(QuoteNode(pkg)))
        $(esc(pkg)) isa PkgRequiredRerunNeeded && return $(esc(pkg))
    end
end

macro require(pkgex::Expr)
    pkgex.head == :(=) ||
        throw(ArgumentError("Expected an `<pkgname> = \"<UUID>\"` expression, not $pkgex"))
    pkgex.args[1] isa Symbol ||
        throw(ArgumentError("Expected a symbol as the package name, not $(pkgex.args[1])"))
    pkgex.args[2] isa String ||
        throw(ArgumentError("Expected a string as the package UUID, not $(pkgex.args[2])"))
    name, id = pkgex.args[1], Base.UUID(pkgex.args[2])
    pkgid = Base.PkgId(id, String(name))
    quote
        $(esc(name)) = get_package($pkgid)
        $(esc(name)) isa PkgRequiredRerunNeeded && return $(esc(name))
    end
end
