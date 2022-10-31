using Pkg

macro addpkgs(pkgs::Symbol...)
    :(addpkgs(@__MODULE__, $(collect(pkgs))))
end

function addpkgs(mod::Module, pkgs::Vector{Symbol})
    project_deps = if isnothing(pathof(mod)) # Main, etc.
        Pkg.project().dependencies
    else # Not a public API, but the best option availible.
        Pkg.Types.read_package(
            abspath(pathof(mod), "..", "..", "Project.toml")).deps
    end
    if length(pkgs) == 1 && first(pkgs) == :(*)
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
