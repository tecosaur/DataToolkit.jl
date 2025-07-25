#!/usr/bin/env -S julia --startup-file=no

include("../../Core/docs/setup.jl")

@setupdev "../../Core" ".."
@get_interlinks

using Org
org2md(joinpath(@__DIR__, "src"))

using Documenter
using DataToolkitREPL, REPL
const REPLMode = Base.get_extension(DataToolkitREPL, :REPLMode)

makedocs(;
    modules=[DataToolkitREPL, REPLMode],
    format=Documenter.HTML(assets = ["assets/favicon.ico"]),
    pages=[
        "Introduction" => "index.md",
        "Commands" => "commands.md",
    ],
    sitename="DataToolkitREPL.jl",
    authors = "tecosaur and contributors: https://github.com/tecosaur/DataToolkit.jl/graphs/contributors",
    warnonly = [:missing_docs, INTERLINKS_WARN],
    plugins = [INTERLINKS],
)

md2rm()

deploydocs(;
    repo="github.com/tecosaur/DataToolkit.jl",
    devbranch = "main",
    dirname = "REPL",
)
