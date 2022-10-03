# This is a special kind of store that's basically just needed for
# the `:julia` loader.
storage(::DataStorage{:null}, ::Any; write::Bool) = Some(nothing)
