function load(loader::DataLoader{:xlsx}, from::FilePath, as::Type{Matrix})
    @use XLSX
    if !isnothing(get(loader, "range"))
        XLSX.readdata(string(from), get(loader, "sheet", 1), get(loader, "range"))
    else
        XLSX.readdata(string(from), get(loader, "sheet", 1))
    end
end

# When <https://github.com/felipenoris/XLSX.jl/pull/217> is merged,
# we can support IO.

createpriority(::Type{DataLoader{:xlsx}}) = 10

function create(::Type{DataLoader{:xlsx}}, source::String)
    if !isnothing(match(r"\.xlsx$"i, source))
        Dict("sheet" => (; prompt="Sheet: ", type=String, default="1"),
             "range" => (; prompt="Range (optional):", type=String, optional=true))
    end
end
