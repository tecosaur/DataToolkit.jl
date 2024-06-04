#!/usr/bin/env -S julia --startup-file=no

include("../../Core/docs/setup.jl")
@setupdev "../../Core" "../../REPL" ".."

using Documenter
using DataToolkitCommon
using DataToolkitREPL, REPL
using Markdown

Core.eval(DataToolkitCommon,
          quote
              tdocs(args...) = $DataToolkitREPL.transformer_docs(args...) |> string |> $Markdown.parse
              pdocs(name) = DataToolkitCore.plugin_info(name) |> string |> $Markdown.parse
          end)

using Org

function editfile(orgfile)
    if basename(dirname(orgfile)) ∈ ("storage", "saveload")
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
end

function org2md_jl(dir::String)
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
                m -> string("```@meta\nEditURL=\"$(editfile(orgfile))\"\n```\n\n", m) |>
                m -> write(mdfile, m)
            push!(MdFiles, mdfile)
        end
        orgconverted += length(orgfiles)
    end
    @info "Converted $orgconverted files from .org to .md"
end

org2md_jl(joinpath(@__DIR__, "src"))

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
            "storage/s3.md",
            "storage/web.md",
        ],
        "Loaders/Writers" => Any[
            "saveload/arrow.md",
            "saveload/chain.md",
            "saveload/compression.md",
            "saveload/csv.md",
            "saveload/delim.md",
            "saveload/gif.md",
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
            "saveload/webp.md",
            "saveload/xlsx.md",
            "saveload/zip.md",
        ],
        "Plugins" => Any[
            "plugins/addpkgs.md",
            "plugins/cache.md",
            "plugins/defaults.md",
            "plugins/memorise.md",
            "plugins/versions.md",
        ],
    ],
    repo="https://github.com/tecosaur/DataToolkit.jl/blob/{commit}{path}#L{line}",
    sitename="DataToolkitCommon.jl",
    authors = "tecosaur and contributors: https://github.com/tecosaur/DataToolkit.jl/graphs/contributors",
    warnonly = [:missing_docs],
)

md2rm()

deploydocs(;
    repo="github.com/tecosaur/DataToolkit.jl",
    devbranch = "main",
    dirname = "Common",
)
