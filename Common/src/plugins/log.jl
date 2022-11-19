const LOG_DEFAULT_EVENTS = ["load", "save", "storage"]

log_events(collection::DataCollection) =
    if "log" in collection.plugins
        get(get(collection, "log", Dict{String, Any}()),
            "events", LOG_DEFAULT_EVENTS)
    else String[] end

log_events(dataset::DataSet) = log_events(dataset.collection)

log_events(adt::AbstractDataTransformer) = log_events(adt.dataset)

function should_log_event(event::String, obj::Union{AbstractDataTransformer, DataSet, DataCollection})
    events = log_events(obj)
    events == true || (events isa Vector && event in events)
end

"""
Log major data set events.

### Settings

```
config.log.events = ["load", "save", "storage"] # the default
```

To log all event types unconditionally, simply set `config.log.events` to
`true`.

### Loggable events
- `load`, when a loader is run
- `save`, when a writer is run
- `storage`, when storage is accessed, in read or write mode

Other transformers or plugins may extend the list of recognised events.
"""
const LOG_PLUGIN = Plugin("log", [
    function (post::Function, f::typeof(load), loader::DataLoader, source::Any, as::Type)
        if should_log_event("load", loader)
            @info "Loading '$(loader.dataset.name)' as $as from $(typeof(source))"
        end
        (post, f, (loader, source, as))
    end,
    function (post::Function, f::typeof(save), writer::DataWriter, target::Any, info::Any)
        if should_log_event("save", writer)
            @info "Writing $(typeof(info)) to '$(writer.dataset.name)' as $(typeof(target))"
        end
        (post, f, (writer, target, info))
    end,
    function (post::Function, f::typeof(storage), storer::DataStorage, as::Type; write::Bool=false)
        if should_log_event("storage", storer)
            @info "Opening '$(storer.dataset.name)' as $(as) from $(first(typeof(storer).parameters)) in $(ifelse(write, "write", "read")) mode"
        end
        (post, f, (storer, as), (; write))
    end
])
