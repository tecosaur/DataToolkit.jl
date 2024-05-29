function lint(ds::DataSet, ::Val{:has_description})
    if isnothing(get(ds, "description"))
        LintItem(ds, :suggestion, :has_description,
                 "Should be given a description",
                 lint_fix_has_description)
    end
end

function lint_fix_has_description(lintitem::LintItem{DataSet})
    if lintitem.source in lintitem.source.collection.datasets
        description = prompt("  Description: ", allowempty=false)
        lintitem.source.parameters["description"] = description
    else
        printstyled("  No longer in the data collection, skipping\n", color=:light_black)
    end
end

function lint(ds::DataSet, ::Val{:no_colon_in_name})
    if ':' in ds.name
        LintItem(ds, :warning, :no_colon_in_name,
                 """Contains a colon in the name
                    This interferes with collection/type references,
                    as a result the data set can only be refered to by UUID.""",
                 lint_rename_dataset)
    end
end

function lint_rename_dataset(lintitem::LintItem{DataSet})
    ds = lintitem.source
    dsindex = findfirst(==(ds), ds.collection.datasets)
    if isnothing(dsindex)
        printstyled("  No longer in the data collection, skipping\n", color=:light_black)
    else
        newname = prompt("  New name: ", allowempty=false)
        while ':' in newname
            newname = prompt("  New name (without a colon!): ", allowempty=false)
        end
        replace!(ds, name=newname)
    end
end

function lint(ds::DataSet, ::Val{:unique_uuid})
    matches = @. getfield(ds.collection.datasets, :uuid) == ds.uuid
    if sum(matches) > 1
        LintItem(ds, :error, :unique_uuid,
                 "UUID is not unique",
                 lint_regenerate_uuid, true)
    end
end

function lint_regenerate_uuid(lintitem::LintItem{DataSet})
    replace!(lintitem.source, uuid = uuid4())
    true
end

function lint(ds::DataSet, ::Val{:has_loader})
    if isempty(ds.loaders)
        LintItem(ds, :warning, :has_loader,
                 "Cannot be loaded, as it has no loaders")
    end
end
