module DownloadsExt

using Downloads
import DataToolkitCommon: download_to

function download_to(url::String, target::Union{String, IO};
                     softreqerr::Bool, kwargs...)
    try
        Downloads.download(url, target; kwargs...)
        true
    catch err
        if err isa Downloads.RequestError && softreqerr
            false
        else
            rethrow()
        end
    end
end

end
