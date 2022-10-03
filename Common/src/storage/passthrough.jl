getstorage(storage::DataStorage{:passthrough}, T::Type) =
    read(resolve(Identifier(get(storage, "ident"))), T)

# TODO putstorage
