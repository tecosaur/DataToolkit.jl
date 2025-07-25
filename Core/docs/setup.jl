using Pkg, TOML

Pkg.activate(@__DIR__)

const DevPkgs = String[]

pkgname(n::Symbol) = String(n)
pkgname(path::String) =
    open(TOML.parse, joinpath(path, "Project.toml"))["name"]

function setupdev(execfile::String, pkgs::Vector{<:Union{Symbol, String}})
    deps = keys(Pkg.project().dependencies)
    wants = map(pkgname, pkgs)
    append!(DevPkgs, wants)
    all(∈(deps), wants) && return
    devpkgs = PackageSpec[]
    for pkg in pkgs
        if pkgname(pkg) ∈ deps
        elseif pkg isa String
            push!(devpkgs, PackageSpec(path = pkg))
        elseif pkg isa Symbol
            push!(devpkgs, PackageSpec(name = String(pkg)))
        end
    end
    Pkg.develop(devpkgs)
    Pkg.instantiate()
    argv = Base.julia_cmd().exec
    opts = Base.JLOptions()
    if opts.project != C_NULL
        push!(argv, "--project=$(unsafe_string(opts.project))")
    end
    push!(argv, execfile)
    @info "Restarting"
    @ccall execv(argv[1]::Cstring, argv::Ref{Cstring})::Cint
end

macro setupdev(pkgs...)
    pkgvals = map(
        p -> if p isa String
            abspath(dirname(String(__source__.file)), p)
        elseif p isa Symbol
            QuoteNode(p)
        else p end, pkgs)
    :(setupdev($(String(__source__.file)), [$(pkgvals...)]))
end

atexit() do
    foreach(Pkg.rm, DevPkgs)
end

# ---

const MdFiles = String[]

html2utf8entity_dirty(text) = # Remove as soon as unnecesary
    replace(text,
            "&hellip;" => "…",
            "&mdash;" => "—",
            "&mdash;" => "–",
            "&shy;" => "-")

function org2md(dir::String)
    orgfiles = filter(f -> endswith(f, ".org"), readdir(dir, join=true))
    orgconverted = 0
    for (root, _, files) in walkdir(dir)
        orgfiles = joinpath.(root, filter(f -> endswith(f, ".org"), files))
        for orgfile in orgfiles
            mdfile = replace(orgfile, r"\.org$" => ".md")
            read(orgfile, String) |>
                c -> Org.parse(OrgDoc, c) |>
                o -> sprint(markdown, o) |>
                html2utf8entity_dirty |>
                s -> replace(s, r"\.org]" => ".md]") |>
                m -> string("```@meta\nEditURL=\"$(basename(orgfile))\"\n```\n\n", m) |>
                m -> write(mdfile, m)
            push!(MdFiles, mdfile)
        end
        orgconverted += length(orgfiles)
    end
    @info "Converted $orgconverted files from .org to .md"
end

md2rm() = foreach(rm, MdFiles)

# ---

const SUBPKGS = Dict(
    :Core => (suffix="Core", subdir="Core", url="core"),
    :REPL => (suffix="REPL", subdir="REPL", url="repl"),
    :Store => (suffix="Store", subdir="Store", url="store"),
    :Common => (suffix="Common", subdir="Common", url="common"),
    :Base => (suffix="Base", subdir="Base", url="base"),
    :Main => (suffix="", subdir="Main", url="main")
)

const DOCS_INTERLINK_PREFIX = "DTk"
const DOCS_BASE_URL = "https://tecosaur.github.io/DataToolkit.jl"

macro get_interlinks(pkgs::Symbol...)
    forms = Expr[]
    for pkg in pkgs
        spec = SUBPKGS[pkg]
        invfile = joinpath(dirname(dirname(@__DIR__)), spec.subdir, "docs", "build", "objects.inv")
        puburl = "$DOCS_BASE_URL/$(spec.url)/"
        invurl = puburl * "objects.inv"
        push!(forms, :($"$DOCS_INTERLINK_PREFIX$(spec.suffix)" =>
            ($puburl,
             if isfile($invfile) Inventory($invfile, root_url=$puburl) end,
             Inventory($invurl, root_url=$puburl))))
    end
    quote
        using Documenter, DocumenterInterLinks, DocInventories
        push!(Documenter.ERROR_NAMES, :extrefs_should_be_fine_nevermind_me)
        const INTERLINKS, INTERLINKS_WARN = let subpkgs = $(Expr(:tuple, forms...))
            uptodate = true
            for (name, (_, invf, invu)) in subpkgs
                if invf != invu
                    uptodate = false
                    break
                end
            end
            if uptodate && "--only-if-inv-changed" in ARGS
                @info "All inventories are up-to-date, skipping generation"
                exit()
            end
            InterLinks(
                "Julia" => ("https:/docs.julialang.org/en/v1/", "https://docs.julialang.org/en/v1/objects.inv"),
                [name => if !isnothing(invf) invf else invu end
                     for (name, (puburl, invf, invu)) in subpkgs]...
            ), if uptodate; :extrefs_should_be_fine_nevermind_me else :external_cross_references end
        end
    end |> esc
end
