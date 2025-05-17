module XMLExt

using XML
import DataToolkitCommon: _read_xml, _write_xml

function _read_xml(from::IO, as::Union{Type{XML.Node}, Type{XML.LazyNode}})
    read(from, as)
end

function _write_xml(dest::IO, data::XML.Node)
    write(dest, data)
end

end
