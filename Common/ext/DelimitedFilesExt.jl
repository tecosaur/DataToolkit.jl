module DelimitedFilesExt

using DelimitedFiles
import DataToolkitCommon: _read_dlm, _write_dlm

function _read_dlm(from::IO; kwargs...)
    result = DelimitedFiles.readdlm(from; kwargs...)
    close(from)
    result
end

function _write_dlm(dest::IO, info; delim::String)
    DelimitedFiles.write(dest, info; delim)
    close(dest)
end

end
