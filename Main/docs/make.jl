#!/usr/bin/env -S julia --startup-file=no

include("../../Core/docs/setup.jl")

@setupdev "../../Core" "../../Common" "../../Store" "../../Base" "../../REPL" ".."
@get_interlinks Core Common REPL

using Org
org2md(joinpath(@__DIR__, "src"))

using Documenter
using DataToolkit, DataToolkitBase, DataToolkitCore

# Ugly fix
Core.eval(Documenter, quote
              function DocSystem.getdocs(binding::Docs.Binding, typesig::Type = Union{}; kwargs...)
                  binding = Base.Docs.aliasof(binding)
                  results = Base.Docs.DocStr[]
                  for mod in Base.Docs.modules
                      dict = Base.Docs.meta(mod; autoinit=false)
                      isnothing(dict) && continue
                      if haskey(dict, binding)
                          multidoc = dict[binding]
                          for msig in multidoc.order
                              typesig <: msig && push!(results, multidoc.docs[msig])
                          end
                      end
                  end
                  results
              end
          end)

makedocs(;
    modules=[DataToolkit, DataToolkitBase, DataToolkitCore],
    format=Documenter.HTML(assets = ["assets/favicon.ico"]),
    pages=[
        "Introduction" => "index.md",
        "Tutorial" => "tutorial.md",
        "Data.toml format" => "datatoml.md",
        "Reference" => "reference.md",
        "Quick Reference Guide" => "quickref.md",
    ],
    sitename="DataToolkit.jl",
    authors = "tecosaur and contributors: https://github.com/tecosaur/DataToolkit.jl/graphs/contributors",
    warnonly = [:missing_docs, INTERLINKS_WARN],
    plugins = [INTERLINKS],
)

deploydocs(;
    repo="github.com/tecosaur/DataToolkit.jl",
    devbranch = "main"
)
