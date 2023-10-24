import REPL.TerminalMenus: request, RadioMenu

const DOWNLOAD_STYLE = (
    textstyle = "\e[90m",
    spinners = ('◐', '◓', '◑', '◒'),
    delay = 1, # Seconds before showing any info
    update_frequency = 0.1, # Seconds between updates
    progress = (style = "\e[34m",
                bar = '━',
                partials = ("\e[90m╺", "╸\e[90m"),
                width = 30),
    eta = (min_time = 10, # Don't bother if total duration less than this
           warmup_seconds = 3, # Seconds before showing ETA
           samples = 300)) # Number of `update_frequency` sized samples to use

struct DownloadProgress <: Function
    io::IO
    filename::String
    recieved_bytes::Ref{Int}
    start::Float64
    last_update::Ref{Float64}
    iters::Ref{Int}
    speed_buckets::Vector{Float64}
    state::NamedTuple{(:show_eta, :eta_now), Tuple{Ref{Bool}, Ref{Bool}}}
end

function DownloadProgress(io::IO, filename::String)
    println(io, " $(DOWNLOAD_STYLE.textstyle)Downloading $filename...\e[m")
    now = time()
    DownloadProgress(io, filename, Ref(0), now, Ref(now), Ref(0),
                     zeros(Float64, DOWNLOAD_STYLE.eta.samples),
                     (show_eta = Ref(false), eta_now = Ref(false)))
end

DownloadProgress(filename::String) = DownloadProgress(stderr, filename)

function (prog::DownloadProgress)(total::Integer, recieved::Integer)
    now = time()
    if now - prog.last_update[] > DOWNLOAD_STYLE.update_frequency
        # Data accounting
        prog.recieved_bytes[], new_bytes = recieved, recieved - prog.recieved_bytes[]
        download_speed_update!(prog, now, new_bytes)
        prog.last_update[] = now
        # Pretty printing
        out = IOBuffer()
        print(out, "\e[G\e[2K", ' ', DOWNLOAD_STYLE.textstyle)
        spinner = DOWNLOAD_STYLE.spinners[
            mod1(prog.iters[] += 1, length(DOWNLOAD_STYLE.spinners))]
        if 0 < recieved == total
            print(out, "✔ $(prog.filename) downloaded ($(join(humansize(total))))")
        elseif total == 0
            print(out, "$spinner $(join(humansize(recieved)))")
        else
            print(out, spinner, ' ')
            download_bar(out, recieved, total)
            byteps = download_speed(prog)
            if prog.state.show_eta[] ||
                now - prog.start > DOWNLOAD_STYLE.eta.warmup_seconds &&
                (total / byteps > DOWNLOAD_STYLE.eta.min_time && (prog.state.show_eta[] = true))
                print(out, ", ")
                download_eta(out, ifelse(prog.state.eta_now[], 0, total - recieved), byteps)
            end
            print(out, " @ ", join(humanspeed(byteps)))
        end
        print(out, "\e[m")
        print(prog.io, String(take!(out)))
        flush(prog.io)
    end
end

function download_bar(io::IO, current::Int, total::Int, text::Bool=true)
    if current == total
        print(io, DOWNLOAD_STYLE.progress.style, DOWNLOAD_STYLE.progress.bar^DOWNLOAD_STYLE.progress.width)
    else
        width = DOWNLOAD_STYLE.progress.width
        scaledprogress = (width * current) / total
        complete = floor(Int, scaledprogress)
        part = round(Int, (length(DOWNLOAD_STYLE.progress.partials)-1) * (scaledprogress % 1) + 1)
        print(io, DOWNLOAD_STYLE.progress.style,
                DOWNLOAD_STYLE.progress.bar^complete,
                DOWNLOAD_STYLE.progress.partials[part],
                DOWNLOAD_STYLE.progress.bar^(width - complete - 1))
    end
    print(io, "\e[m", DOWNLOAD_STYLE.textstyle)
    if text
        csize, cunits = humansize(current, digits=3)
        tsize, tunits = humansize(total, digits=2)
        print(io, ' ', csize, ifelse(cunits == tunits, "", cunits),
              '/', tsize, ifelse(cunits == tunits, " ", ""), tunits)
    end
end

function download_speed_update!(prog::DownloadProgress, update::Float64, new_bytes::Integer)
    avg_speed = new_bytes / (update - prog.last_update[])
    bfirst = floor(Int, (prog.last_update[] - prog.start) / DOWNLOAD_STYLE.update_frequency)
    blast = floor(Int, (update - prog.start) / DOWNLOAD_STYLE.update_frequency)
    if bfirst == blast - 1
        prog.speed_buckets[mod1(blast, length(prog.speed_buckets))] = avg_speed
    else
        start = mod1(bfirst+1, length(prog.speed_buckets))
        stop = mod1(blast, length(prog.speed_buckets))
        binds = if start <= stop
            start:stop
        else
            lind = fill(false, length(prog.speed_buckets))
            lind[start:end] .= true
            lind[begin:stop] .= true
            lind
        end
        prog.speed_buckets[binds] .= avg_speed
    end
    nothing
end

function download_speed(prog::DownloadProgress)
    last = min(floor(Int, (prog.last_update[] - prog.start) / DOWNLOAD_STYLE.update_frequency),
               length(prog.speed_buckets))
    sum(prog.speed_buckets[1:last]) / last
end

function humanspeed(Bps::Number; digits::Int=1)
    bps = 8 * Bps
    units = ("b/s", "Kb/s", "Mb/s", "Gb/s", "Tb/s", "Pb/s")
    magnitude = floor(Int, log(1000, max(1, bps)))
    if 1000 <= bps < 10.0^(digits-1) * 1000^magnitude
        magdigits = floor(Int, log10(bps / 1000^magnitude)) + 1
        round(bps / 1000^magnitude; digits = digits - magdigits)
    else
        round(bps / 1000^magnitude; digits)
    end, units[1+magnitude]
end

function download_eta(io::IO, remaining::Integer, bps::Number)
    print(io, "ETA ",
          if bps == 0; "∞"
          elseif remaining < bps; "now"
          else
              eta_seconds = round(Int, remaining / bps)
              eta_period = Dates.canonicalize(Dates.Period(Second(eta_seconds)))
              replace(string(eta_period), r" ([a-z])[a-z]+,?" => s"\1")
          end)
end

function download_to(storage::DataStorage{:web}, target::Union{IO, String}, retries::Int=2)
    @import Downloads
    url = @getparam(storage."url"::String)
    try
        Downloads.download(
            url, target;
            headers = @getparam(storage."headers"::SmallDict{String, Any}),
            timeout = @getparam(storage."timeout"::Real, Inf),
            progress = DownloadProgress(storage.dataset.name))
        print(stderr, "\e[G\e[2K\e[A\e[2K")
        target isa IO && seekstart(target)
    catch err
        if err isa Downloads.RequestError && retries > 0
            @warn "Download failed, retrying ($retries retries remaining)" url err
            target isa IO && seekstart(target)
            download_to(storage, target, retries - 1)
        else
            rethrow()
        end
    end
end

function getstorage(storage::DataStorage{:web}, ::Type{IO})
    try
        io = IOBuffer()
        download_to(storage, io)
        io
    catch err
        url = @getparam(storage."url"::String)
        @error "Download failed" url err
        Some(nothing)
    end
end

function getstorage(storage::DataStorage{:web}, ::Type{FilePath})
    tmpfile = tempname()
    download_to(storage, tmpfile)
    FilePath(tmpfile)
end

function Store.fileextension(storage::DataStorage{:web})
    something(match(r"\.\w+(?:\.[bgzx]z|\.[bg]?zip|\.zstd)?$",
                    @getparam(storage."url"::String)),
              (; match=".cache")).match[2:end]
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
        ["url" => source]
    end
end

const WEB_DOC = md"""
Fetch data from the internet

This pairs well with the `store` plugin.

# Required packages

- `Downloads` (part of Julia's stdlib)

# Parameters

- `url` :: Path to the online data.
- `headers` :: HTTP headers that should be set.
- `timeout` :: Maximum number of seconds to try to download for before abandoning.

# Usage examples

Downloading the data on-demand each time it is accessed.

```toml
[[iris.storage]]
driver = "web"
url = "https://raw.githubusercontent.com/mwaskom/seaborn-data/master/iris.csv"
```
"""
