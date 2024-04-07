using Documenter
using DataToolkitCommon
using Markdown
using Org

let orgconverted = 0
    html2utf8entity_dirty(text) = # Remove as soon as unnecesary
        replace(text,
                "&hellip;" => "…",
                "&mdash;" => "—",
                "&mdash;" => "–",
                "&shy;" => "-")
    editfile(orgfile) = if basename(dirname(orgfile)) ∈ ("storage", "saveload")
        name = first(splitext(basename(orgfile)))
        jfile = joinpath(dirname(@__DIR__), "src", "transformers", basename(dirname(orgfile)), "$name.jl")
        if isfile(jfile)
            docline = open(io -> findfirst(line -> !isnothing(match(r"^const [A-Z_]+_DOC = md\"", line)),
                                           collect(eachline(io))), jfile)
            # It would be good to use `jfile * "#L" * string(something(docline, ""))`
            # however, at the moment this makes Documenter.jl look for a file
            # with `#` in the path, and then complain that it doesn't exist.
            jfile
        else
            orgfile
        end
    else
        orgfile
    end
    for (root, _, files) in walkdir(joinpath(@__DIR__, "src"))
        orgfiles = joinpath.(root, filter(f -> endswith(f, ".org"), files))
        for orgfile in orgfiles
            mdfile = replace(orgfile, r"\.org$" => ".md")
            read(orgfile, String) |>
                c -> Org.parse(OrgDoc, c) |>
                o -> sprint(markdown, o) |>
                html2utf8entity_dirty |>
                s -> replace(s, r"\.org]" => ".md]") |>
                m -> string("```@meta\nEditURL=\"$(editfile(orgfile))\"\n```\n\n", m) |>
                m -> write(mdfile, m)
        end
        orgconverted += length(orgfiles)
    end
    @info "Converted $orgconverted files from .org to .md"
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
            "saveload/arrow.md",
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
            "plugins/addpkgs.md",
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
