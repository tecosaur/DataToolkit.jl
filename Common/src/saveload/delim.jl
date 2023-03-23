function load(loader::DataLoader{:delim}, from::IO, ::Type{Matrix})
    @import DelimitedFiles
    dtype::Type = convert(Type, QualifiedType(get(loader, "type", "Any")))
    delim::Char = first(get(loader, "delim", ","))
    eol::Char = first(get(loader, "eol", "\n"))
    header::Bool = get(loader, "header", false)
    skipstart::Int = get(loader, "skipstart", 0)
    skipblanks::Bool = get(loader, "skipblanks", false)
    quotes::Bool = get(loader, "quotes", true)
    comment_char::Char = first(get(loader, "comment_char", "#"))
    result = DelimitedFiles.readdlm(
        from, delim, dtype, eol;
        header, skipstart, skipblanks,
        quotes, comment_char)
    close(from)
    result
end

function save(writer::DataWriter{:delim}, dest::IO, info::Union{Vector, Matrix})
    @import DelimitedFiles
    delim::Char = first(get(writer, "delim", ","))
    DelimitedFiles.writedlm(dest, info; delim)
    close(dest)
end
