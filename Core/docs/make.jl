#!/usr/bin/env -S julia --startup-file=no

include("setup.jl")
@setupdev ".."
@get_interlinks Core Common Main

using Org
org2md(joinpath(@__DIR__, "src"))

using Documenter
using DataToolkitCore

makedocs(;
    modules=[DataToolkitCore],
    format=Documenter.HTML(assets = ["assets/favicon.ico"]),
    pages=[
        "Introduction" => "index.md",
        "Datasets" => "datasets.md",
        "Transformers" => "transformers.md",
        "Plugins & Advice" => "plugins.md",
        "Lazy Packages" => "packages.md",
        "Linting" => "linting.md",
        "Utilities" => "utilities.md",
        "Errors" => "errors.md",
        "Internals" => "internals.md",
    ],
    sitename="DataToolkitCore.jl",
    authors = "tecosaur and contributors: https://github.com/tecosaur/DataToolkit.jl/graphs/contributors",
    warnonly = [:missing_docs, INTERLINKS_WARN],
    plugins = [INTERLINKS],
)

md2rm()

deploydocs(;
    repo="github.com/tecosaur/DataToolkit.jl",
    devbranch = "main",
    dirname = "Core",
)
