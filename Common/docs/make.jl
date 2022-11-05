using Documenter
using DataToolkitCommon
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
            "loaders/iotofile.md",
            "loaders/json.md",
            "loaders/julia.md",
            "loaders/chain.md",
            "loaders/passthrough.md",
            "loaders/sqlite.md",
            "loaders/xlsx.md",
            "loaders/zip.md",
        ],
        "Plugins" => Any[
            "plugins/defaults.md",
            "plugins/loadcache.md",
            "plugins/log.md",
            "plugins/memorise.md",
        ],
    ],
    repo="https://github.com/tecosaur/DataToolkitCommon.jl/blob/{commit}{path}#L{line}",
    sitename="DataToolkitCommon.jl",
    authors = "tecosaur and contributors: https://github.com/tecosaur/DataToolkitCommon.jl/graphs/contributors"
)

deploydocs(;
    repo="github.com/tecosaur/DataToolkitCommon.jl",
    devbranch = "main"
)
