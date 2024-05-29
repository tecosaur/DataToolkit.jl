using Documenter
using DataToolkit, DataToolkit.DataToolkitBase
using Org

# Ugly fix
Core.eval(Documenter, quote
              getdocs(binding::Docs.Binding, typesig::Type = Union{}; kwargs...) =
                  ((@info "b: $binding" ); Base.Docs.doc(binding, typesig))
          end)

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
    modules=[DataToolkit, DataToolkitBase],
    format=Documenter.HTML(),
    pages=[
        "Introduction" => "index.md",
        "Tutorial" => "tutorial.md",
        "Data.toml format" => "datatoml.md",
        "Reference" => "reference.md",
        "Quick Reference Guide" => "quickref.md",
    ],
    sitename="DataToolkit.jl",
    authors = "tecosaur and contributors: https://github.com/tecosaur/DataToolkit.jl/graphs/contributors",
    warnonly = [:missing_docs],
)

deploydocs(;
    repo="github.com/tecosaur/DataToolkit.jl",
    devbranch = "main"
)
