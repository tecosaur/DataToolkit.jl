#!/usr/bin/env -S julia --startup-file=no

include("../../Core/docs/setup.jl")
@setupdev "../../Core" ".."

using Org
org2md(joinpath(@__DIR__, "src"))

using Documenter, DocumenterInterLinks
using DataToolkitREPL, REPL
const REPLMode = Base.get_extension(DataToolkitREPL, :REPLMode)

const interlinks = @all_interlinks;

makedocs(;
    modules=[DataToolkitREPL, REPLMode],
    format=Documenter.HTML(assets = ["assets/favicon.ico"]),
    pages=[
        "Introduction" => "index.md",
        "Commands" => "commands.md",
    ],
    sitename="DataToolkitREPL.jl",
    authors = "tecosaur and contributors: https://github.com/tecosaur/DataToolkit.jl/graphs/contributors",
    warnonly = [:missing_docs],
    plugins = [interlinks],
)

md2rm()

deploydocs(;
    repo="github.com/tecosaur/DataToolkit.jl",
    devbranch = "main",
    dirname = "REPL",
)
