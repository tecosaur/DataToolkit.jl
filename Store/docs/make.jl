using Documenter
using DataToolkitStore
using Org

orgfiles = filter(f -> endswith(f, ".org"),
                  readdir(joinpath(@__DIR__, "src"), join=true))

for orgfile in orgfiles
    mdfile = replace(orgfile, r"\.org$" => ".md")
    read(orgfile, String) |>
        c -> Org.parse(OrgDoc, c) |>
        o -> sprint(markdown, o) |>
        s -> replace(s, r"\.org]" => ".md]") |>
        m -> write(mdfile, m)
end

makedocs(;
    modules=[DataToolkitStore],
    format=Documenter.HTML(),
    pages=[
        "Introduction" => "index.md",
        "The Inventory" => "inventory.md",
    ],
    repo="https://github.com/tecosaur/DataToolkitStore.jl/blob/{commit}{path}#L{line}",
    sitename="DataToolkitStore.jl",
    authors = "tecosaur and contributors: https://github.com/tecosaur/DataToolkitStore.jl/graphs/contributors"
)

deploydocs(;
    repo="github.com/tecosaur/DataToolkitStore.jl",
    devbranch = "main"
)
