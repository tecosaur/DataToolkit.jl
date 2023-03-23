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

function download_to(storage::DataStorage{:web}, target::Union{IO, String})
    @import Downloads
    Downloads.download(
        get(storage, "url"), target;
        headers = get(storage, "headers", Dict{String, String}()),
        timeout = get(storage, "timeout", Inf),
        progress = download_progress(storage.dataset.name))
    print(stderr, "\e[G\e[2K\e[A\e[2K")
    target isa IO && seekstart(target)
end

function checkchecksum(storage::DataStorage{:web}, data::IO)
    checksum = get(storage, "checksum")
    if checksum == "auto" || checksum isa Integer
        checkchecksum(storage, crc32c(data))
    elseif !isnothing(checksum)
        @warn "Invalid url storage checksum: $checksum, ignoring."
        (false, false)
    else
        (false, false)
    end
end

"""
    checkchecksum(storage::DataStorage{:web}, actual_checksum::Integer; noerror::Bool=false)
    checkchecksum(storage::DataStorage{:web}, data::IO; noerror::Bool=false)
Check if the stated checksum of `storage` (if any) matches `actual_checksum`
(or the computed checksum of `data`, if given instead).

Should this not be the case, in an interactive session where the data collection
is writable the user will be asked if they want to change the checksum. Otherwise,
unless `noerror` is set an error will be raised.

The return value is a `Tuple{Bool, Bool}` signifying
- whether the checksum matches
- whether the checksum was modified

Hence, the three expected return values are:
    (true, false)
    (true, true)
    (false, false)
"""
function checkchecksum(storage::DataStorage{:web}, actual_checksum::Integer; noerror::Bool=true)
    checksum = get(storage, "checksum")
    if checksum == "auto"
        storage.parameters["checksum"] = actual_checksum
        @info "Writing checksum for $(storage.dataset.name)'s url storage."
        write(storage)
        (true, true)
    elseif checksum isa Integer
        if actual_checksum == checksum
            (true, false)
        else
            if isinteractive() && iswritable(storage.dataset.collection)
                printstyled(stderr, "!", color=:yellow, bold=true)
                print(" Checksum mismatch with $(storage.dataset.name)'s url storage.\n",
                      "  Expected the CRC32c checksum to be $checksum, got $actual_checksum.\n",
                      "  How would you like to proceed?\n\n")
                options = ["(o) Overwrite checksum to $actual_checksum", "(a) Abort and throw an error"]
                choice = request(RadioMenu(options, keybindings=['o', 'a']))
                print('\n')
                if choice == 1 # Overwrite
                    storage.parameters["checksum"] = actual_checksum
                    write(storage)
                    (true, true)
                else
                    noerror || error(string("Checksum mismatch with $(storage.dataset.name)'s url storage!",
                                            " Expected $checksum, got $actual_checksum."))
                    (false, false)
                end
            else
                noerror || error(string("Checksum mismatch with $(storage.dataset.name)'s url storage!",
                                        " Expected $checksum, got $actual_checksum."))
                (false, false)
            end
        end
    else
        (false, false)
    end
end

function getstorage(storage::DataStorage{:web}, ::Type{IO})
    @something(
        let dlcf = get_dlcache_file(storage)
            if !isnothing(dlcf)
                open(dlcf, "r")
            end
        end,
        try
            io = IOBuffer()
            download_to(storage, io)
            checkchecksum(storage, io) |> first && seekstart(io)
            io
        catch err
            url = get(storage, "url")
            @error "Download failed" url err
            Some(nothing)
        end)
end

function getstorage(storage::DataStorage{:web}, ::Type{FilePath})
    if get(storage, "cache", false) != false
        FilePath(get_dlcache_file(storage))
    else
        tmpfile = tempname()
        download_to(storage, tmpfile)
        FilePath(tmpfile)
    end
end

const WEB_DEFAULT_CACHEFOLDER = "downloads"

function get_dlcache_file(storage::DataStorage{:web})
    function getpath(; full::Bool=false)
        path = if get(storage, "cache") == true
            urlext = something(match(r"\.\w+(?:\.[bgzx]z|\.[bg]?zip|\.zstd)?$",
                                    get(storage, "url")),
                            (; match=".cache")).match
            string(string(hash(get(storage, "url")), base=16),
                '-',
                string(chash(DataCollection(), storage.parameters, zero(UInt)), base=16),
                urlext)
        elseif get(storage, "cache") isa String
            get(storage, "cache")
        elseif get(storage, "cache", false) == false
        else
            @warn "Invalid cache parameter: $(get(storage, "cache")), ignoring."
        end
        if !isnothing(path)
            if full
                joinpath(
                    if !isnothing(storage.dataset.collection.path)
                        dirname(storage.dataset.collection.path)
                    else
                        pwd()
                    end,
                    get(storage, "cachefolder", WEB_DEFAULT_CACHEFOLDER),
                    path)
            else
                path
            end
        end
    end
    if !isnothing(getpath())
        fullpath = getpath(full=true)
        if !isfile(fullpath)
            if !isdir(dirname(fullpath))
                mkpath(dirname(fullpath))
            end
            download_to(storage, fullpath)
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
                _, modified = checkchecksum(storage, checksum)
                if modified
                    oldpath, fullpath = fullpath, getpath(full=true)
                    mv(oldpath, fullpath)
                end
            catch e
                rm(fullpath)
                rm(checksumfile)
                rethrow(e)
            end
        end
        fullpath
    end
end

getstorage(storage::DataStorage{:web}, ::Type{Vector{UInt8}}) =
    read(getstorage(storage, IO))

getstorage(storage::DataStorage{:web}, ::Type{String}) =
    read(getstorage(storage, IO), String)

supportedtypes(::Type{<:DataStorage{:web, <:Any}}) =
    QualifiedType.([IO, Vector{UInt8}, String, FilePath])

createpriority(::Type{<:DataStorage{:web}}) = 30

function create(::Type{<:DataStorage{:web}}, source::String)
    if !isnothing(match(r"^(?:https?|ftps?)://", source))
        Dict{String, Any}("url" => source)
    end
end
