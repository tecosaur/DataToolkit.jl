const LOG_DEFAULT_EVENTS = ["load", "save", "storage"]

log_events(collection::DataCollection) =
    if "log" in collection.plugins
        get(get(collection, "log", Dict{String, Any}()),
            "events", LOG_DEFAULT_EVENTS)
    else String[] end

log_events(dataset::DataSet) = log_events(dataset.collection)

log_events(adt::AbstractDataTransformer) = log_events(adt.dataset)

"""
    Plugin("log", [...])
Log major data set events.

### Settings

```
config.log.events = ["load", "save", "storage"] # the default
```

### Loggable events
- `load`, when a loader is run
- `save`, when a writer is run
- `storage`, when storage is accessed, in read or write mode

Other transformers or plugins may extend the list of recognised events.
"""
const LOG_PLUGIN = Plugin("log", [
    function (post::Function, f::typeof(load), loader::DataLoader, source::Any, as::Type)
        if "load" in log_events(loader)
            @info "Loading $(loader.dataset.name) as $as from $(typeof(source))"
        end
        (post, f, (loader, source, as))
    end,
    function (post::Function, f::typeof(save), writer::DataWriter, target::Any, info::Any)
        if "save" in log_events(writer)
            @info "Writing $(typeof(info)) to $(writer.dataset.name) as $(typeof(target))"
        end
        (post, f, (writer, target, info))
    end,
    function (post::Function, f::typeof(storage), storer::DataStorage, as::Type; write::Bool=false)
        if "storage" in log_events(storer)
            @info "Opening $(storer.dataset.name) as $(as) from $(first(typeof(storer).parameters)) in $(ifelse(write, "write", "read")) mode"
        end
        (post, f, (storer, as), pairs((; write)))
    end
])
