#!/usr/bin/env -S julia --startup-file=no

include("../../Core/docs/setup.jl")

@setupdev "../../Core" "../../REPL" ".."
@get_interlinks

using Org
org2md(joinpath(@__DIR__, "src"))

using Documenter
using DataToolkitStore
using DataToolkitREPL, REPL
using Markdown

Core.eval(DataToolkitStore,
          quote
              pdocs(name) = DataToolkitCore.plugin_info(name) |> string |> $Markdown.parse
          end)

makedocs(;
    modules=[DataToolkitStore],
    format=Documenter.HTML(assets = ["assets/favicon.ico"]),
    pages=[
        "Introduction" => "index.md",
        "The Inventory" => "inventory.md",
        "REPL Commands" => "repl.md",
        "Plugins" => Any[
            "plugin_store.md",
            "plugin_cache.md",
        ],
    ],
    repo="https://github.com/tecosaur/DataToolkit.jl/blob/{commit}{path}#L{line}",
    sitename="DataToolkitStore.jl",
    authors = "tecosaur and contributors: https://github.com/tecosaur/DataToolkit.jl/graphs/contributors",
    warnonly = [:missing_docs, INTERLINKS_WARN],
    plugins = [INTERLINKS],
)

md2rm()

deploydocs(;
    repo="github.com/tecosaur/DataToolkit.jl",
    devbranch = "main",
    dirname = "Store",
)
