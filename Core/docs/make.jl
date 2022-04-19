using Documenter, DataToolkitBase

makedocs(;
    modules=[DataToolkitBase],
    format=Documenter.HTML(),
    pages=[
        "Introduction" => "index.md",
        "REPL" => "repl.md",
        "Library" => Any[
            "Public" => "libpublic.md",
            "Data Transduction" => "transducing.md",
            "Internals" => "libinternal.md",
        ],
    ],
    repo="https://github.com/tecosaur/DataToolkit.jl/blob/{commit}{path}#L{line}",
    sitename="DataSets.jl",
    authors = "tecosaur and contributors: https://github.com/tecosaur/DataToolkit.jl/graphs/contributors"
)

deploydocs(;
    repo="github.com/tecosaur/DataToolkitBase.jl"
)
