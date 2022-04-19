# The Data REPL

## Getting help

The `help` command will give an overview of the data commands available, and one
may call `help CMD` for an description of a particular data command.
```
data> help
data> help stack
```

## Acting on the data collection stack

To list the current data collections on the stack, simply call the `stack`
command with no arguments.

```
data> stack
```

The `stack` command also allows you to operate on the data collection stack.
The `load` subcommand adds new layer from a data collection specification file,
one may run:

```
data> stack load path/to/Data.toml
```

The freshly loaded data collection will be placed at the top of the stack. Reloading a collection thus moves it to the top of the stack. However, dedicated subcommands exist for moving layers of the data stack.
To move a collection to the top of the stack, one may use the `promote` subcommand.
```
data> stack promote NAME OR UUID
```
Similarly, to move a collection down the stack, one may use the `demote` subcommand.
```
data> stack demote NAME OR UUID
```

## Looking at data sets in a collection

The available data sets within a collection can be viewed with the `list` command
```
data> list
```

This lists the data sets present in the collection at the top of the stack. To view the data sets of another collection, provide its name to the `list` command.
```
data> list OTHER DATA COLLECTION
```

One may also view a particular data set in more detail using the `show`  command.
Simply give a data `Identifier` and it will resolve it --- much like the `dataset` function, but without requiring you to leave the Data REPL.
```
show IDENTIFIER
```

## Creating a new data set

### From scratch

### From a storage location

## Removing a data set

## Creating new REPL commands

The Data REPL can be easily extended in just a few steps.

First, one must create a `ReplCmd` object, like so:
```julia
ReplCmd{:demo}("A demo command", _ -> "Hello")
```

```@doc
ReplCmd
```

Then, simply push this to the global vector `REPL_CMDS`. You can now call the `demo` command in the Data REPL.
```
data> demo
"hello"
```

An expanded help message can be provided by adding a method to the `help` function as follows:
```julia
function help(::ReplCmd{:demo})
    println(stderr, "This is a demo command created for the Data REPL documentation.")
end
```

This will be shown when calling the `help` command on `demo`. By default, the
short description given when creating `ReplCmd{:demo}` is used. The short
description is always used in the help table.
```
data> help
 Command  Shorthand  Action                                                  
 ──────────────────────────────────
 demo                A demo command
 ...                 ...
 
data> help demo
This is a demo command created for the Data REPL
```

Completions can also be provided by adding a method to the `completion` function.
```julia
function completions(::ReplCmd{:demo}, input::AbstractString)
    filter(s -> startswith(s, "input"), ["hi", "hello", "howdy"])
end
```

For reference, the default implementations of `help` and `completions` are as follows:
```julia
help(r::ReplCmd) = println(stderr, r.description)
completions(::ReplCmd, ::AbstractString) = String[]
```
