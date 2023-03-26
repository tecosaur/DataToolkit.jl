using Documenter
using DataToolkit
using Org

for (root, _, files) in walkdir(joinpath(@__DIR__, "src"))
    orgfiles = joinpath.(root, filter(f -> endswith(f, ".org"), files))
    for orgfile in orgfiles
        mdfile = replace(orgfile, r"\.org$" => ".md")
        read(orgfile, String) |>
            c -> Org.parse(OrgDoc, c) |>
            o -> sprint(markdown, o) |>
            s -> replace(s, r"\.org]" => ".md]") |>
            m -> write(mdfile, m)
    end
end

makedocs(;
    modules=[DataToolkit],
    format=Documenter.HTML(),
    pages=[
        "Introduction" => "index.md",
        "Reference" => "reference.md",
    ],
    repo="https://github.com/tecosaur/DataToolkit.jl/blob/{commit}{path}#L{line}",
    sitename="DataToolkit.jl",
    authors = "tecosaur and contributors: https://github.com/tecosaur/DataToolkit.jl/graphs/contributors"
)

deploydocs(;
    repo="github.com/tecosaur/DataToolkit.jl",
    devbranch = "main"
)
