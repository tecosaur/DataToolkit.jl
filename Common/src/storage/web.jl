function download_progress(filename::AbstractString)
    start_time = time()
    min_seconds_before_eta = 5
    last_print = 0
    itercount = 0
    aprint(io::IO, val) = print(io, ' ', "\e[90m", val, "\e[m")
    partialbars = ["\e[90m╺", "╸\e[90m"]
    spinners = ['◐', '◓', '◑', '◒']
    println(stderr, " \e[90mDownloading $filename...\e[m")
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
                aprint(out, "$spinner $now bytes")
            else
                eta_segment = if time() - start_time >= min_seconds_before_eta
                    eta_seconds = round(Int, (total-now)/(now+1)*(time() - start_time))
                    eta_period = Dates.canonicalize(Dates.Period(Second(eta_seconds)))
                    eta_short = replace(string(eta_period), r" ([a-z])[a-z]+,?" => s"\1")
                    " ETA: $eta_short"
                else "" end
                complete = 30 * now/total
                aprint(out, string(
                    spinner, " \e[34m", '━'^floor(Int, complete),
                    partialbars[round(Int, 1+(length(partialbars)-1)*(complete%1))],
                    '━'^floor(Int, 30 - complete),
                    "  $now/$total bytes ($(round(100*now/total, digits=1))%)",
                    eta_segment))
            end
            print(stderr, String(take!(out)))
            flush(stderr)
        end
    end
end

function checkchecksum(storage::DataStorage{:url}, data::IO)
    checksum = get(storage, "checksum")
    if checksum == "auto" || checksum isa Integer
        checkchecksum(storage, crc32c(data))
        true
    elseif !isnothing(checksum)
        @warn "Invalid url storage checksum: $checksum, ignoring."
        false
    else
        false
    end
end

function checkchecksum(storage::DataStorage{:url}, actual_checksum::Integer)
    checksum = get(storage, "checksum")
    if checksum == "auto"
        storage.parameters["checksum"] = actual_checksum
        @info "Writing checksum for $(storage.dataset.name)'s url storage."
        write(storage)
    elseif checksum isa Integer
        if actual_checksum != checksum
            if isinteractive()
                printstyled(stderr, "!", color=:yellow, bold=true)
                print(" Checksum mismatch with $(storage.dataset.name)'s url storage.\n  \
                        Expected the CRC32c checksum to be $checksum, got $actual_checksum.\n  \
                        How would you like to proceed?\n\n")
                options = ["(o) Overwrite checksum to $actual_checksum", "(a) Abort and throw an error"]
                choice = request(RadioMenu(options, keybindings=['o', 'a']))
                print('\n')
                if choice == 1 # Overwrite
                    storage.parameters["checksum"] = actual_checksum
                    write(storage)
                else
                    error("Checksum mismatch with $(storage.dataset.name)'s url storage! \
                        Expected $checksum, got $actual_checksum.")
                end
            else
                error("Checksum mismatch with $(storage.dataset.name)'s url storage! \
                       Expected $checksum, got $actual_checksum.")
            end
        end
    end
end

function getstorage(storage::DataStorage{:url}, ::Type{IO})
    @use Downloads
    @something get_dlcache_file(storage) try
        io = IOBuffer()
        Downloads.download(
            get(storage, "url"), io;
            headers = get(storage, "headers", Dict{String, String}()),
            timeout = get(storage, "timeout", Inf),
            progress = download_progress(storage.dataset.name))
        print(stderr, "\e[G\e[2K\e[A\e[2K")
        seekstart(io)
        checkchecksum(storage, io) && seekstart(io)
        io
    catch _
        Some(nothing)
    end
end

const WEB_DEFAULT_CACHEFOLDER = "downloads"

function get_dlcache_file(storage::DataStorage{:url})
    @use Downloads
    path = if get(storage, "cache") != false
        something(get(storage, "cachefile"),
                  if get(storage, "cache") == true
                      # Restrict characters to the POSIX portable filename character set.
                      replace(storage.dataset.name, r"[^A-Za-z0-9_-]" => '_') *
                          ".cache"
                  end,
                  Some(nothing))
    end
    if !isnothing(path)
        fullpath = joinpath(
            if !isnothing(storage.dataset.collection.path)
                dirname(storage.dataset.collection.path)
            else
                pwd()
            end,
            get(storage, "cachefolder", WEB_DEFAULT_CACHEFOLDER),
            path)
        if !isfile(fullpath)
            if !isdir(dirname(fullpath))
                mkpath(dirname(fullpath))
            end
            Downloads.download(
                get(storage, "url"), fullpath;
                headers = get(storage, "headers", Dict{String, String}()),
                timeout = get(storage, "timeout", Inf),
                progress = download_progress(storage.dataset.name))
            print(stderr, "\e[G\e[2K\e[A\e[2K")
            chmod(fullpath, 0o100444 & filemode(fullpath)) # Make read-only
        end
        if !isnothing(get(storage, "checksum"))
            checksumfile = joinpath(dirname(fullpath),
                                    '.' * basename(fullpath) * ".checksum")
            if !isfile(checksumfile) || mtime(checksumfile) < mtime(fullpath)
                rm(checksumfile, force=true)
                checksum = open(f -> crc32c(f), fullpath, "r")
                write(checksumfile, string(checksum))
                chmod(checksumfile, 0o100444 & filemode(fullpath)) # Make read-only
            end
            checksum = parse(Int, read(checksumfile, String))
            try
                checkchecksum(storage, checksum)
            catch e
                rm(fullpath)
                rm(checksumfile)
                rethrow(e)
            end
        end
        open(fullpath, "r")
    end
end

getstorage(storage::DataStorage{:url}, ::Type{Vector{UInt8}}) =
    read(getstorage(storage, IO))

getstorage(storage::DataStorage{:url}, ::Type{String}) =
    read(getstorage(storage, IO), String)

supportedtypes(::Type{<:DataStorage{:url, <:Any}}) =
    QualifiedType.([IO, Vector{UInt8}, String])
