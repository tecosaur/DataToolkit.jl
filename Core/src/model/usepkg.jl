function get_package(pkg::Base.PkgId)
    if !Base.root_module_exists(pkg)
        @warn string("The package $pkg is required to load your dataset. ",
                     "`DataToolkitBase` will import this module for you, ",
                     "but this may not always work as expected.",
                     "\n\n",
                     "To silence this message, add `using $(pkg.name)` ",
                     "at the top of your code somewhere.")
        Base.require(pkg)
    end
    Base.root_module(pkg)
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
This package may now be used with `@use \$name`.

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

"""
    @use pkg1 pkg2...
Fetch previously registered modules.

`@use pkg1` loads the module `pkg1` into the current scope as `pkg1`.
Multiple packages may be loaded all at once by seperating each package
name with a space.
"""
macro use(pkgnames::Symbol...)
    Expr(:block,
         map(pkgnames) do pkg
             Expr(:(=), esc(pkg),
                  :($(@__MODULE__).get_package(
                      @__MODULE__, Symbol($(esc(String(pkg)))))))
         end...)
end
