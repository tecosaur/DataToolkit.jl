using Pkg

macro addpkgs(pkgs::Symbol...)
    :(addpkgs(@__MODULE__, $(collect(pkgs))))
end

function addpkgs(mod::Module, pkgs::Vector{Symbol})
    project_deps = Pkg.project().dependencies
    if length(pkgs) == 1 && first(pkgs) == :(*)
        pkgs = Symbol.(keys(project_deps))
    end
    for pkg in pkgs
        DataToolkitBase.addpkg(mod, pkg, project_deps[String(pkg)])
    end
end
