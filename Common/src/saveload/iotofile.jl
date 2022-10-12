function load(loader::DataLoader{Symbol("io->file")}, from::IO, ::Type{FilePath})
    path = abspath(dirname(loader.dataset.collection.path),
                   @something(expanduser(get(loader, "path")),
                              joinpath(tempdir(),
                                       string("julia_datatoolkit_iotofile_",
                                              loader.dataset.uuid))))
    open(path, "w") do io
        write(io, from)
    end
    FilePath(path)
end
