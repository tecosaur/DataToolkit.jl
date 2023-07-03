using Documenter
using DataToolkit
using Org

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
                m -> write(mdfile, m)
        end
        orgconverted += length(orgfiles)
    end
    @info "Converted $orgconverted files from .org to .md"
end

makedocs(;
    modules=[DataToolkit],
    format=Documenter.HTML(),
    pages=[
        "Introduction" => "index.md",
        "Tutorial" => "tutorial.md",
        "Data.toml format" => "datatoml.md",
        "Reference" => "reference.md",
        "Quick Reference Guide" => "quickref.md",
    ],
    repo="https://github.com/tecosaur/DataToolkit.jl/blob/{commit}{path}#L{line}",
    sitename="DataToolkit.jl",
    authors = "tecosaur and contributors: https://github.com/tecosaur/DataToolkit.jl/graphs/contributors"
)

deploydocs(;
    repo="github.com/tecosaur/DataToolkit.jl",
    devbranch = "main"
)
