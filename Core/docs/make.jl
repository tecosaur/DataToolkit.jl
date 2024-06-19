#!/usr/bin/env -S julia --startup-file=no

include("setup.jl")
@setupdev ".."

using Org
org2md(joinpath(@__DIR__, "src"))

using Documenter
using DataToolkitCore

makedocs(;
    modules=[DataToolkitCore],
    format=Documenter.HTML(assets = ["assets/favicon.ico"]),
    pages=[
        "Introduction" => "index.md",
        "Usage" => "usage.md",
        "Extensions" => Any[
            "Transformer backends" => "newtransformer.md",
            "Packages" => "packages.md",
            "Data Advice" => "advising.md",
        ],
        "Internals" => "libinternal.md",
        "Errors" => "errors.md",
    ],
    sitename="DataToolkitCore.jl",
    authors = "tecosaur and contributors: https://github.com/tecosaur/DataToolkit.jl/graphs/contributors",
    warnonly = [:missing_docs],
)

md2rm()

deploydocs(;
    repo="github.com/tecosaur/DataToolkit.jl",
    devbranch = "main",
    dirname = "Core",
)
