# ------------------
# Setting up the Data REPL and framework
# ------------------

@doc """
A command that can be used in the Data REPL (accessible through '$REPL_KEY').

A `ReplCmd` consists of the following fields:

- `name`, a string that designates the command, and triggers it in the repl
- `description`, a short overview of the functionality as a `string` or `display`able object.
- `execute`, either a list of sub-ReplCmds, or a function which will perform the
  command's action. The function must take a single argument, the rest of the
  command as an `AbstractString` (for example, 'cmd arg1 arg2' will call the
  execute function with "arg1 arg2").
- `completions` (optional), a function that takes a partial argument string
  and returns a list of candidate completions.

```julia
ReplCmd(name::String, description::String, execute::Function, [completions::Function])
ReplCmd(name::String, description::String, execute::Vector{<:ReplCmd})
```

# Examples

```julia
ReplCmd("echo", "print the argument", identity)

ReplCmd("math", "A collection of basic integer arithmetic",
    [ReplCmd("add", "a + b + ...", nums -> sum(parse.(Int, split(nums))))],
     ReplCmd("mul", "a * b * ...", nums -> prod(parse.(Int, split(nums)))))
```
""" ReplCmd

function ReplCmd(name::String, description::Any,
                 execute::Union{Function, Vector{<:ReplCmd}},
                 completions::Function = if execute isa Vector
                     sofar -> complete_repl_cmd(sofar, commands = execute)
                 else
                     Returns(String[])
                 end)
    if execute isa Function
        ReplCmd{Function}(
            name, description, execute, completions)
    else
        ReplCmd{Vector{ReplCmd}}(
            name, description, Vector{ReplCmd}(execute), completions)
    end
end

function ReplCmd(name, description, execute, completions::Vector{String})
    ReplCmd(name, description, execute,
            sofar -> filter(c -> startswith(c, sofar), completions))
end

function add_repl_cmd!(cmd::ReplCmd)
    pos = searchsortedfirst(REPL_CMDS, cmd, by = c -> c.name)
    insert!(REPL_CMDS, pos, cmd)
end

function help end
function find_repl_cmd end
function execute_repl_cmd end
function toplevel_execute_repl_cmd end
function complete_repl_cmd end
function init_repl end

# Interaction utilities

function prompt end
function prompt_char end
function confirm_yn end
function peelword end

# Private functions, but might as well

function displaytable end
function help_cmd_table end
function help_show end
function transformer_docs end
function transformers_printall end
