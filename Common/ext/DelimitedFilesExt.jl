module DelimitedFilesExt

using DelimitedFiles
import DataToolkitCommon: _read_dlm, _write_dlm

function _read_dlm(from::IO, delim::Char, dtype::Type, eol::Char; kwargs...)
    result = DelimitedFiles.readdlm(from, delim, dtype, eol; kwargs...)
    close(from)
    result
end

function _write_dlm(dest::IO, info; delim::Char)
    DelimitedFiles.writedlm(dest, info, delim)
    close(dest)
end

end
