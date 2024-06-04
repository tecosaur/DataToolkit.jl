using Pkg

Pkg.activate(@__DIR__)

const DevPkgs = String[]

pkgname(n::Symbol) = String(n)
pkgname(path::String) =
    open(io -> Base.TOML.parse(Base.TOML.Parser(io)),
         joinpath(path, "Project.toml"))["name"]

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
