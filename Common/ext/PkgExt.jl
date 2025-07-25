module PkgExt

using Pkg
import DataToolkitCommon: best_semver_version

function best_semver_version(spec::String, versions::Vector{VersionNumber})
    requirement = Pkg.Versions.semver_spec(spec)
    validmask = [v ∈ requirement for v in versions]
    if any(validmask)
        maximum(versions[validmask])
    end
end

end
