function getstorage(storage::DataStorage{:git}, ::Type{IO})
    # Need to use the system `git` or `Git_jll`, since `LibGit2` doesn't
    # support `git archive`.
    git = if !isnothing(Sys.which("git"))
        `git`
    else
        @import Git_jll
        Git_jll.git()
    end
    remote = get(storage, "remote", "")
    !isempty(remote) || throw(ArgumentError("Git storage must specify a remote"))
    tree = get(storage, "revision", "HEAD")
    path = get(storage, "path", ".")
    clone = get(storage, "clone", false)
    if clone !== true
        # Try `git archive --remote`
        cmd = open(`$git archive --format=tar --remote=$remote $tree $path`)
        magic = zeros(UInt8, 17)
        mark(cmd.out)
        nb = readbytes!(cmd.out, magic)
        if nb == 17 && String(magic) == "pax_global_header"
            reset(cmd.out)
            return cmd.out
        end
        # Fall back on `git clone` + `git archive`
        @info "Git archive --remote failed, falling back on git clone + git archive"
    end
    clonedir = mktempdir()
    success(`$git clone $remote $clonedir`) || error("Failed to clone $remote")
    # Now try a local `git archive`
    cmd = open(Cmd(`$git archive --format=tar $tree $path`, dir=clonedir))
    magic = zeros(UInt8, 17)
    mark(cmd.out)
    nb = readbytes!(cmd.out, magic)
    if nb == 17 && String(magic) == "pax_global_header"
        reset(cmd.out)
        return cmd.out
    end
    # Well, something has gone wrong :(
    error("Git archive produced unrecognised output")
end

function create(::Type{<:DataStorage{:git}}, source::String)
    if !isnothing(match(r"^git://|^git(?:ea)?@|\w+@git\.|\.git$", source))
        ["remote" => source,
         "revision" => (; prompt="Revision: ", type=String, optional=true),
         "clone" => (; prompt="Clone", type=Bool, optional=true,
                     default = occursin("github.com", source),
                     skipvalue = false),
         "path" => (; prompt="Path: ", type=String, optional=true)]
    end
end

const GIT_DOC = md"""
Access a tarball of a git repository

# Parameters

- `remote`: A remote repository path, e.g. `git://...` or `git@...`.
- `revision`: A "tree-ish" specification of a particular revision to
  use, `HEAD` by default.
  See https://git-scm.com/docs/gitrevisions#_specifying_revisions.
- `path` (optional): A subdirectory of the repository to archive, instead of the
  entire repository.
- `clone`: Whether to use a clone instead of `git archive --remote`.
  `false` by default.

## Tree-ish forms

The particular "tree-ish" forms accepted can depend on the remote, but these are
the forms that seem to work.

| Form                   | Examples                                      |
|:-----------------------|:----------------------------------------------|
| `<describeOutput>`     | `v1.7.4.2-679-g3bee7fb`                       |
| `<refname>`            | `master`, `heads/master`, `refs/heads/master` |
| `<rev>`                | `HEAD`, `v1.5.1`                              |

When applied to a local/cloned repository, more forms are possible.

| Form                   | Examples                                     |
|:-----------------------|:---------------------------------------------|
| `<sha1>`               | `dae86e1950b1277e545cee180551750029cfe735`   |
| `<refname>@{<date>}`   | `master@{yesterday}`, `HEAD@{5 minutes ago}` |
| `<refname>@{<n>}`      | `master@{1}`                                 |
| `@{<n>}`               | `@{1}`                                       |
| `@{-<n>}`              | `@{-1}`                                      |
| `<refname>@{upstream}` | `master@{upstream}`, `@{u}`                  |
| `<rev>~<n>`            | `master~3`                                   |
| `<rev>^{<type>}`       | `v0.99.8^{commit}`                           |
| `<rev>^{}`             | `v0.99.8^{}`                                 |
| `<rev>^{/<text>}`      | `HEAD^{/fix nasty bug}`                      |
| `:/<text>`             | `:/fix nasty bug`                            |

# Usage examples

```toml
[[myrepo.storage]]
driver = "git"
remote = "git@forge.example:user/project.git"
revision = "v1.4"
path = "subdir/thing"
```

```
[[myrepo.storage]]
driver = "git"
remote = "https://forge.example:user/project.git"
revision = "2b8a2a4390"
clone = true
```
"""
