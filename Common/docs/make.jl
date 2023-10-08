using Documenter
using DataToolkitCommon
using Markdown
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

Core.eval(DataToolkitCommon,
          quote
              tdocs(args...) = DataToolkitBase.transformer_docs(args...) |> string |> $Markdown.parse
              pdocs(name) = DataToolkitBase.plugin_info(name) |> string |> $Markdown.parse
          end)

makedocs(;
    modules=[DataToolkitCommon],
    format=Documenter.HTML(),
    pages=[
        "Introduction" => "index.md",
        "Storage" => Any[
            "storage/filesystem.md",
            "storage/git.md",
            "storage/null.md",
            "storage/passthrough.md",
            "storage/raw.md",
            "storage/web.md",
        ],
        "Loaders/Writers" => Any[
            "saveload/chain.md",
            "saveload/compression.md",
            "saveload/csv.md",
            "saveload/delim.md",
            "saveload/iotofile.md",
            "saveload/jpeg.md",
            "saveload/json.md",
            "saveload/julia.md",
            "saveload/netpbm.md",
            "saveload/passthrough.md",
            "saveload/png.md",
            "saveload/qoi.md",
            "saveload/sqlite.md",
            "saveload/tar.md",
            "saveload/tiff.md",
            "saveload/xlsx.md",
            "saveload/zip.md",
        ],
        "Plugins" => Any[
            "plugins/cache.md",
            "plugins/defaults.md",
            "plugins/log.md",
            "plugins/memorise.md",
            "plugins/store.md",
            "plugins/versions.md",
        ],
        "REPL" => "repl.md",
    ],
    repo="https://github.com/tecosaur/DataToolkitCommon.jl/blob/{commit}{path}#L{line}",
    sitename="DataToolkitCommon.jl",
    authors = "tecosaur and contributors: https://github.com/tecosaur/DataToolkitCommon.jl/graphs/contributors",
    warnonly = [:missing_docs],
)

deploydocs(;
    repo="github.com/tecosaur/DataToolkitCommon.jl",
    devbranch = "main"
)
