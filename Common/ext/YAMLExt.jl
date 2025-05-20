module YAMLExt

using YAML
import DataToolkitCommon: _read_yaml, _write_yaml

function _read_yaml(from::IO, ::Type{T}) where {T <: AbstractDict}
    dicttype = if !isconcretetype(T)
        Dict{Any, Any}
    else T end
    YAML.load(from; dicttype)
end

_write_yaml(dest::IO, info::AbstractDict) =
    YAML.write(dest, info)

end
