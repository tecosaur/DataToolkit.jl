using Documenter
using DataToolkitCommon
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
    modules=[DataToolkitCommon],
    format=Documenter.HTML(),
    pages=[
        "Introduction" => "index.md",
        "Storage" => Any[
            "storage/filesystem.md",
            "storage/null.md",
            "storage/passthrough.md",
            "storage/raw.md",
            "storage/web.md",
        ],
        "Loaders" => Any[
            "loaders/compression.md",
            "loaders/csv.md",
            "loaders/delim.md",
            "loaders/json.md",
            "loaders/julia.md",
            "loaders/nested.md",
            "loaders/passthrough.md",
        ],
        "Plugins" => Any[
            "plugins/defaults.md",
            "plugins/loadcache.md",
        ],
    ],
    repo="https://github.com/tecosaur/DataToolkitCommon.jl/blob/{commit}{path}#L{line}",
    sitename="DataSets.jl",
    authors = "tecosaur and contributors: https://github.com/tecosaur/DataToolkitCommon.jl/graphs/contributors"
)

deploydocs(;
    repo="github.com/tecosaur/DataToolkitCommon.jl",
    devbranch = "main"
)
