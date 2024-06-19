# This is a special kind of store that's basically just needed for
# the `:julia` loader.
storage(::DataStorage{:null}, ::Any; write::Bool) = Some(nothing)

# To avoid method ambiguity
storage(::DataStorage{:null}, ::Type; write::Bool) = Some(nothing)

const NULL_S_DOC = md"""
A special driver sometimes needed for the `julia` loader

This driver always produces `Some(nothing)`.
"""
