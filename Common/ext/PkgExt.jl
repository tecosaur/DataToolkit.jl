module PkgExt

using Pkg
import DataToolkitCommon: pkg_semver_spec

pkg_semver_spec(ver::String) =
    Pkg.Versions.semver_spec(ver)

end
