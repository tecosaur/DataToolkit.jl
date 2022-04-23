const TOMLValue = DataToolkitBase.TOML.Internals.Printer.TOMLValue
# TOML_TYPES = Base.uniontypes(TOMLValue)

function getstorage(storage::DataStorage{:raw}, ::Type{<:TOMLValue})
    get(storage.parameters, "value", nothing)
end

function putstorage(storage::DataStorage{:raw}, ::Type{<:TOMLValue})
    storage
end

# NOTE This is hacky, but it's a special case
function save(::DataWriter{:passthrough}, dest::DataStorage{:raw}, info::Any)
    dest.parameters["value"] = info
end
