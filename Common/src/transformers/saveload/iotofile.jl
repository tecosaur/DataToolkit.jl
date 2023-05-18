function load(loader::DataLoader{Symbol("io->file")}, from::IO, ::Type{FilePath})
    path = abspath(dirof(loader.dataset.collection),
                   @something(expanduser(get(loader, "path")),
                              joinpath(tempdir(),
                                       string("julia_datatoolkit_iotofile_",
                                              loader.dataset.uuid))))
    if !isfile(path)
        open(path, "w") do io
            write(io, from)
        end
    end
    FilePath(path)
end
