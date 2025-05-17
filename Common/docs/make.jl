#!/usr/bin/env -S julia --startup-file=no

include("../../Core/docs/setup.jl")

@setupdev "../../Core" "../../REPL" ".."
@get_interlinks Core REPL Main

const DocPlugins = [
    "AddPkgs" => "addpkgs",
    "Defaults" => "defaults",
    "Memorise" => "memorise",
    "Versions" => "versions",
]

const DocSaveload = [
    "Arrow",
    "Chain",
    "Compressed",
    "CSV",
    "Delim",
    "Gif",
    "IO to File" => "io->file",
    "JLD2",
    "Jpeg",
    "Json",
    "Julia",
    "Netpbm",
    "Passthrough",
    "PNG",
    "QOI",
    "Serialization",
    "Sqlite",
    "Tar",
    "Tiff",
    "Webp",
    "XLSX",
    "XML",
    "Zip",
]

const DocStorage = [
    "Filesystem",
    "Git",
    "Null",
    "Passthrough",
    "Raw",
    "S3",
    "Web",
]

using Documenter
using DataToolkitCore
using DataToolkitCommon
using DataToolkitREPL, REPL
using Markdown

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

for (entries, subdir, idprefix, docfn) in (
    (DocPlugins, "plugins", "plugin", p ->
        """
        !!! info "Using this plugin"
            To use the plugin, either modify the `plugins` entry of the
            collection's [Data.toml](@extref) to include `"$p"`, or use the Data
            REPL's [`plugin add`](@extref repl-plugin-add)/[`plugin remove`](@extref
            repl-plugin-remove) subcommands.

        """ * string(DataToolkitCore.plugin_info(p))),
    (DocSaveload, "saveload", "saveload", t -> DataToolkitREPL.transformer_docs(Symbol(t), :loader)),
    (DocStorage, "storage", "storage", t -> DataToolkitREPL.transformer_docs(Symbol(t), :storage)))
    mkpath(joinpath(@__DIR__, "src", subdir))
    for entry in entries
        name, key = if entry isa Pair entry else entry, lowercase(entry) end
        file = replace(lowercase(name), r"[^a-z0-9]" => "") * ".md"
        open(joinpath(@__DIR__, "src", subdir, file), "w") do io
            content = replace(docfn(key) |> string, r"^#" => "##")
            println(io, """
            # [$name](@id $idprefix-$(lowercase(name)))

            $content
            """)
        end
    end
end

entryfname(n::String) = replace(lowercase(n), r"[^a-z0-9]" => "") * ".md"
entryfname(p::Pair) = entryfname(p.first)

makedocs(;
    modules=[DataToolkitCommon],
    format=Documenter.HTML(assets = ["assets/favicon.ico"]),
    pages=[
        "Introduction" => "index.md",
        "Contributing" => "contributing.md",
        "Storage" => map(e -> "storage/$(entryfname(e))", DocStorage),
        "Loaders/Writers" => map(e -> "saveload/$(entryfname(e))", DocSaveload),
        "Plugins" => map(e -> "plugins/$(entryfname(e))", DocPlugins),
    ],
    repo="https://github.com/tecosaur/DataToolkit.jl/blob/{commit}{path}#L{line}",
    sitename="DataToolkitCommon.jl",
    authors = "tecosaur and contributors: https://github.com/tecosaur/DataToolkit.jl/graphs/contributors",
    warnonly = [:missing_docs, INTERLINKS_WARN],
    plugins = [INTERLINKS],
)

md2rm()

deploydocs(;
    repo="github.com/tecosaur/DataToolkit.jl",
    devbranch = "main",
    dirname = "Common",
)
