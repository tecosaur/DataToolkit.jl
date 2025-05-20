using MultiDocumenter
import MultiDocumenter: MultiDocRef

# GitHub pages doesn't like symlinks
for (root, dirs, files) in walkdir(".")
    for file in files
        filepath = joinpath(root, file)
        if islink(filepath)
            linktarget = abspath(dirname(filepath), readlink(filepath))
            rm(filepath)
            cp(linktarget, filepath; force=true)
        end
    end
end

docs = [
    MultiDocRef(upstream = joinpath(dirname(@__DIR__), "Main", "docs", "build"),
                path = "main",
                name = "DataToolkit",
                fix_canonical_url = false),
    MultiDocRef(upstream = joinpath(dirname(@__DIR__), "REPL", "docs", "build"),
                path = "repl",
                name = "REPL",
                fix_canonical_url = false),
    # MultiDocRef(upstream = joinpath(dirname(@__DIR__), "Base", "docs", "build"),
    #             path = "base",
    #             name = "Base",
    #             fix_canonical_url = false),
    MultiDocRef(upstream = joinpath(dirname(@__DIR__), "Common", "docs", "build"),
                path = "common",
                name = "Common",
                fix_canonical_url = false),
    MultiDocRef(upstream = joinpath(dirname(@__DIR__), "Store", "docs", "build"),
                path = "store",
                name = "Store",
                fix_canonical_url = false),
    MultiDocRef(upstream = joinpath(dirname(@__DIR__), "Core", "docs", "build"),
                path = "core",
                name = "Core",
                fix_canonical_url = false),
    MultiDocumenter.DropdownNav("Collections", [])
]

outpath = joinpath(dirname(@__DIR__), "docs")

MultiDocumenter.make(
    outpath,
    docs;
    search_engine = MultiDocumenter.SearchConfig(
        index_versions = ["stable", "dev"],
        engine = MultiDocumenter.FlexSearch),
    brand_image = MultiDocumenter.BrandImage("/DataToolkit.jl", "logo-small.svg"),
    rootpath = "/DataToolkit.jl/")

cp(joinpath(@__DIR__, "logo-small.svg"),
   joinpath(outpath, "logo-small.svg"))

touch(joinpath(outpath, ".nojekyll"))

# --- Edits ---

let multidoc_style_overrides = [
    """
#multi-page-nav {
    width: 100%;
    height: var(--navbar-height);
    z-index: 10;
    padding: 0 1rem;
    position: sticky;
    display: flex;
    top: 0;
    background-color: #282f2f;
    border-bottom: 1px solid #5e6d6f;
}""" => """
#multi-page-nav {
    width: 100%;
    height: var(--navbar-height);
    z-index: 10;
    padding: 0 1rem;
    position: sticky;
    display: flex;
    top: 0;
    background-color: whitesmoke;
    border-bottom: 1px solid #dbdbdb;
}

html.theme--documenter-dark #multi-page-nav {
    background-color: #282f2f;
    border-bottom: 1px solid #5e6d6f;
}""",
    "font-size: 14px;" => "font-size: 1.1em;",
    "\n    text-transform: uppercase;" => "",
    "color: #fff;" => "color: inherit;\n    opacity: 1;",
    "color: #ccc;" => "color: inherit;\n    opacity: 0.75;",
    "max-height: calc(var(--navbar-height) - 10px);" =>
        "max-height: calc(var(--navbar-height) - 15px);"
    ]
    multidoc_css_file = joinpath(outpath, "assets", "default", "multidoc.css")
    chmod(multidoc_css_file, 0o664)
    multidoc_style = read(multidoc_css_file, String)
    write(multidoc_css_file, replace(multidoc_style, multidoc_style_overrides...))
end

# --- Push to multidoc-pub ---

outbranch = "multidoc-pub"
has_outbranch = true

if !success(`git checkout --orphan $outbranch`)
    has_outbranch = false
    @info "Creating orphaned branch $outbranch"
    if !success(`git switch --orphan $outbranch`)
        @error "Cannot create new orphaned branch $outbranch."
        exit(1)
    end
end

run(`git add --all`)

if success(`git commit -m 'Aggregate documentation'`)
    @info "Pushing updated documentation."
    run(`git push origin --force $outbranch`)
else
    @info "No changes to aggregated documentation."
end
