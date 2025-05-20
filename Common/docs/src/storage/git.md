# [Git](@id storage-git)

Access a tarball of a git repository

# Parameters

  * `remote`: A remote repository path, e.g. `git://...` or `git@...`.
  * `revision`: A "tree-ish" specification of a particular revision to use, `HEAD` by default. See https://git-scm.com/docs/gitrevisions#*specifying*revisions.
  * `path` (optional): A subdirectory of the repository to archive, instead of the entire repository.
  * `clone`: Whether to use a clone instead of `git archive --remote`. `false` by default.

## Tree-ish forms

The particular "tree-ish" forms accepted can depend on the remote, but these are the forms that seem to work.

| Form               | Examples                                      |
|:------------------ |:--------------------------------------------- |
| `<describeOutput>` | `v1.7.4.2-679-g3bee7fb`                       |
| `<refname>`        | `master`, `heads/master`, `refs/heads/master` |
| `<rev>`            | `HEAD`, `v1.5.1`                              |

When applied to a local/cloned repository, more forms are possible.

| Form                   | Examples                                     |
|:---------------------- |:-------------------------------------------- |
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


