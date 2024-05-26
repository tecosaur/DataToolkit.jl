#!/usr/bin/env -S julia --startup-file=no

using Documenter
using DataToolkitBase
using Org

using REPL
const DataToolkitREPL = Base.get_extension(DataToolkitBase, :DataToolkitREPL)

orgfiles = filter(f -> endswith(f, ".org"),
                  readdir(joinpath(@__DIR__, "src"), join=true))

let orgconverted = 0
    html2utf8entity_dirty(text) = # Remove as soon as unnecesary
        replace(text,
                "&hellip;" => "…",
                "&mdash;" => "—",
                "&mdash;" => "–",
                "&shy;" => "-")
    for (root, _, files) in walkdir(joinpath(@__DIR__, "src"))
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
        end
        orgconverted += length(orgfiles)
    end
    @info "Converted $orgconverted files from .org to .md"
end

makedocs(;
    modules=[DataToolkitBase, DataToolkitREPL],
    format=Documenter.HTML(),
    pages=[
        "Introduction" => "index.md",
        "Usage" => "usage.md",
        "Data.toml" => "datatoml.md",
        "REPL" => "repl.md",
        "Extensions" => Any[
            "Transformer backends" => "newtransformer.md",
            "Packages" => "packages.md",
            "Data Advice" => "advising.md",
        ],
        "Internals" => "libinternal.md",
        "Errors" => "errors.md",
    ],
    sitename="DataToolkitBase.jl",
    authors = "tecosaur and contributors: https://github.com/tecosaur/DataToolkitBase.jl/graphs/contributors",
    warnonly = [:missing_docs],
)

deploydocs(;
    repo="github.com/tecosaur/DataToolkitBase.jl",
    devbranch = "main"
)
