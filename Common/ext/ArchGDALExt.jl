module ArchGDALExt

using ArchGDAL
import DataToolkitCommon: _read_geopkg, _write_geopkg

function _read_geopkg(file::String, T::Type)
    ArchGDAL.IDataset <: T || return
    ArchGDAL.read(file)
end

function _write_geopkg(destfile::String, info::ArchGDAL.AbstractDataset)
    info isa ArchGDAL.AbstractDataset || return
    ArchGDAL.write(destfile, info)
    close(dest)
end

end
