"""
    @addpkgs pkgs...

For each named package, register it with `DataToolkitBase`.
Each package must be a dependency of the current module, recorded in its
Project.toml.

This allows the packages to be used with `DataToolkitBase.@import`.

Instead of providing a list of packages, the symbol `*` can be provided to
register all dependencies.

This must be run at runtime to take effect, so be sure to place it in the
`__init__` function of a package.

# Examples

```julia
@addpkgs JSON3 CSV
@addpkgs * # Register all dependencies
```
"""
macro addpkgs(pkgs::Symbol...)
    :(addpkgs(@__MODULE__, $(collect(pkgs))))
end

"""
    addpkgs(mod::Module, pkgs::Vector{Symbol})

For each package in `pkgs`, which are dependencies recorded in `mod`'s
Project.toml, register the package with `DataToolkitBase.addpkg`.

If `pkgs` consists of the single symbol `:*`, then all dependencies of `mod`
will be registered.

This must be run at runtime to take effect, so be sure to place it in the
`__init__` function of a package.
"""
function addpkgs(mod::Module, pkgs::Vector{Symbol})
    project_deps = _project_deps(mod)
    if length(pkgs) == 1 && first(pkgs) == :*
        pkgs = Symbol.(keys(project_deps))
    end
    for pkg in pkgs
        if haskey(project_deps, String(pkg))
            DataToolkitBase.addpkg(mod, pkg, project_deps[String(pkg)])
        else
            @warn "(@addpkgs) $mod does not have $pkg in its dependencies, skipping."
        end
    end
end

function _project_deps(mod::Module)
    project_file = if isnothing(pathof(mod)) # Main, etc.
        JLBase.active_project()
    else
        abspath(pathof(mod), "..", "..", "Project.toml")
    end
    project_deps = if isfile(project_file)
        Dict{String, JLBase.UUID}(
            pkg => JLBase.UUID(id)
            for (pkg, id) in get(JLBase.parsed_toml(project_file),
                                 "deps", Dict{String, Any}()))
    else
        Dict{String, JLBase.UUID}()
    end
end
