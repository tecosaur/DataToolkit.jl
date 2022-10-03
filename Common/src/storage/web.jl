function download_progress(filename::AbstractString)
    start_time = time()
    last_print = 0
    itercount = 0
    aprint(io::IO, val) = print(io, ' ', "\e[90m", val, "\e[m")
    partialbars = ['╺', '▏','▎','▍','▌','▋','▊','▉']
    spinners = ['◐', '◓', '◑', '◒']
    function (total::Integer, now::Integer)
        if time() - start_time > 2 && time() - last_print > 0.1
            last_print = time()
            itercount += 1
            spinner = spinners[1 + itercount % length(spinners)]
            out = IOBuffer()
            print(out, "\e[G\e[2K")
            if 0 < now == total
                aprint(out, "✔ $filename downloaded ($total bytes)")
            elseif total == 0
                aprint(out, "$spinner $now bytes of $filename downloaded")
            else
                eta_seconds = round(Int, (total-now)/(now+1)*(time() - start_time))
                eta_period = Dates.canonicalize(Dates.Period(Second(eta_seconds)))
                eta_short = replace(string(eta_period), r" ([a-z])[a-z]+,?" => s"\1")
                complete = 30 * now/total
                aprint(out, string(
                    spinner, ' ', '█'^floor(Int, complete),
                    partialbars[round(Int, 1+(length(partialbars)-1)*(complete%1))],
                    '━'^floor(Int, 30 - complete),
                    "  $now/$total bytes ($(round(100*now/total, digits=1))%) of $filename downloaded",
                    "  [ETA: $(eta_short)]"))
            end
            print(stderr, String(take!(out)))
            flush(stderr)
        end
    end
end

function getstorage(storage::DataStorage{:url}, ::Type{IO})
    @use Downloads
    try
        io = IOBuffer()
        Downloads.download(
            get(storage, "url"), io;
            headers = get(storage, "headers", Dict{String, String}()),
            timeout = get(storage, "timeout", Inf),
            progress = download_progress(storage.dataset.name))
        seekstart(io)
        io
    catch _
    end
end

