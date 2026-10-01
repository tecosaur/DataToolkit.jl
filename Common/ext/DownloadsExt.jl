module DownloadsExt

using Downloads
import DataToolkitCommon: download_to
using DataToolkitCommon: InsufficientSpace

function download_to(url::String, target::IO;
                     softreqerr::Bool, kwargs...)
    try
        Downloads.download(url, target; kwargs...)
        true
    catch err
        if err isa Downloads.RequestError && softreqerr
            false
        elseif err isa TaskFailedException && err.task.exception isa InsufficientSpace
            # Downloads raises an error from `progress` as its task's failure.
            throw(err.task.exception)
        else
            rethrow()
        end
    end
end

end
