using Pkg
Pkg.activate(@__DIR__)

using LiveServer

try
    servedocs(doc_env=true, foldername=@__DIR__)
finally
    rm(joinpath(@__DIR__, "build"), force=true, recursive=true)
    for (root, _, files) in walkdir(joinpath(@__DIR__, "src"))
        for file in files
            if endswith(file, ".md")
                rm(joinpath(root, file))
            end
        end
    end
end
