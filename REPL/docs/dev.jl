#!/usr/bin/env -S julia --startup-file=no

using Pkg
Pkg.activate(@__DIR__)

function cleanup()
    rm(joinpath(@__DIR__, "build"), force=true, recursive=true)
    for (root, _, files) in walkdir(joinpath(@__DIR__, "src"))
        for file in files
            if endswith(file, ".md")
                rm(joinpath(root, file))
            end
        end
    end
end
cleanup()

using LiveServer

Base.exit_on_sigint(false)
try
    servedocs(doc_env=true, foldername=@__DIR__)
finally
    cleanup()
end
