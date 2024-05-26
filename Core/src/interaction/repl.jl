# ------------------
# Setting up the Data REPL and framework
# ------------------

@doc """
A command that can be used in the Data REPL (accessible through '$REPL_KEY').

A `ReplCmd` must have a:
- `name`, a symbol designating the command keyword.
- `trigger`, a string used as the command trigger (defaults to `String(name)`).
- `description`, a short overview of the functionality as a `string` or `display`able object.
- `execute`, either a list of sub-ReplCmds, or a function which will perform the
  command's action. The function must take a single argument, the rest of the
  command as an `AbstractString` (for example, 'cmd arg1 arg2' will call the
  execute function with "arg1 arg2").

# Constructors

```julia
ReplCmd{name::Symbol}(trigger::String, description::Any, execute::Function)
ReplCmd{name::Symbol}(description::Any, execute::Function)
ReplCmd(name::Union{Symbol, String}, trigger::String, description::Any, execute::Function)
ReplCmd(name::Union{Symbol, String}, description::Any, execute::Function)
```

# Examples

```julia
ReplCmd(:echo, "print the argument", identity)
ReplCmd(:addone, "return the input plus one", v -> 1 + parse(Int, v))
ReplCmd(:math, "A collection of basic integer arithmetic",
    [ReplCmd(:add, "a + b + ...", nums -> sum(parse.(Int, split(nums))))],
     ReplCmd(:mul, "a * b * ...", nums -> prod(parse.(Int, split(nums)))))
```

# Methods

```julia
help(::ReplCmd) # -> print detailed help
allcompletions(::ReplCmd) # -> list all candidates
completions(::ReplCmd, sofar::AbstractString) # -> list relevant candidates
```
""" ReplCmd

ReplCmd{name}(description::Any, execute::Union{Function, Vector{ReplCmd}}) where {name} =
    ReplCmd{name}(String(name), description, execute)

ReplCmd(name::Union{Symbol, String}, args...) =
    ReplCmd{Symbol(name)}(args...)

function help end
function completions end
function allcompletions end
function find_repl_cmd end
function execute_repl_cmd end
function toplevel_execute_repl_cmd end
function complete_repl_cmd end
function init_repl end

# For some reason beyond me, documenter doesn't pick this up
# if the docstring is left in the DataToolkitREPL extension 😕.
# REVIEW check to see if this is magically fixed in a newer version
# of `Documenter`.
@doc """
    allcompletions(r::ReplCmd)

Obtain all possible `String` completion candidates for `r`.
This defaults to the empty vector `String[]`.

`allcompletions` is only called when `completions(r, sofar::AbstractString)` is
not implemented.
""" allcompletions

# Interaction utilities

function prompt end
function prompt_char end
function confirm_yn end
function peelword end

# Private functions, but might as well

function help_cmd_table end
function help_show end
function transformer_docs end
function transformers_printall end
