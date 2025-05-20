module DataToolkitREPL

using PrecompileTools

using Markdown

export ReplCmd, REPL_CMDS, add_repl_cmd!, help,
    prompt, prompt_char, confirm_yn, peelword

"""
    REPL_KEY

The key that is used to enter the data REPL.
"""
const REPL_KEY = '}'

"""
    REPL_NAME

A symbol identifying the Data REPL. This is used in a few places,
such as the command history.
"""
const REPL_NAME = :data_toolkit

"""
     REPL_PROMPT

The REPL prompt shown.
"""
const REPL_PROMPT = "data>"

"""
    REPL_PROMPTSTYLE

An ANSI control sequence string that sets the style of the "$REPL_PROMPT"
REPL prompt.
"""
const REPL_PROMPTSTYLE = Base.text_colors[:magenta]

"""
    REPL_QUESTION_COLOR

The color that should be used for question text presented in a REPL context.
This should be a symbol present in `Base.text_colors`.
"""
const REPL_QUESTION_COLOR = :light_magenta

"""
    REPL_USER_INPUT_COLOUR

The color that should be set for user response text in a REPL context.
This should be a symbol present in `Base.text_colors`.
"""
const REPL_USER_INPUT_COLOUR = :light_yellow

"""
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
ReplCmd(name::String, description::String, execute::Vector{ReplCmd})
```

# Examples

```julia
ReplCmd("echo", "print the argument", identity)

ReplCmd("math", "A collection of basic integer arithmetic",
    [ReplCmd("add", "a + b + ...", nums -> sum(parse.(Int, split(nums))))],
     ReplCmd("mul", "a * b * ...", nums -> prod(parse.(Int, split(nums)))))
```
"""
struct ReplCmd
    name::String
    description::Any
    execute::Union{Function, Vector{ReplCmd}}
    completions::Function
end

function ReplCmd(name::String, description::Any, execute::Vector{ReplCmd})
    completions = sofar -> invokelatest(complete_repl_cmd, sofar, commands = execute)
    ReplCmd(name, description, execute, completions)
end

function ReplCmd(name::String, description::Any, execute::Function)
    ReplCmd(name, description, execute, Returns(String[]))
end

function ReplCmd(name, description, execute, completions::Vector{String})
    ReplCmd(name, description, execute,
            sofar -> filter(c -> startswith(c, sofar), completions))
end

function add_repl_cmd!(cmd::ReplCmd)
    pos = searchsortedfirst(REPL_CMDS, cmd, by = c -> c.name)
    insert!(REPL_CMDS, pos, cmd)
end

precompile(add_repl_cmd!, (ReplCmd,))

"""
The set of commands available directly in the Data REPL.
"""
const REPL_CMDS = ReplCmd[]

# ------------------
# Setting up the Data REPL and framework
# ------------------

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

# Extensible API

function show_extra end

# Private functions, but might as well

function displaytable end
function help_cmd_table end
function help_show end
function transformer_docs end
function transformers_printall end

# ------------------
# Workaround for 1.11+ REPL package extension dodginess
# ------------------

@static if VERSION >= v"1.11"
    function __init__()
        # Trigger extension loading. This is an absolute pain, but
        # the only way I could find to get this to work.
        replid = Base.PkgId(Base.UUID("3fa0cd96-eef1-5676-8a61-b3b8758bbffb"), "REPL")
        if isassigned(Base.REPL_MODULE_REF) && !haskey(Base.loaded_modules, replid)
            # It seems that the required hooks (i.e. EXT_DORMITORY entries) are
            # only added /after/ this package is loaded and this `__init__`
            # finishes, so we need to require REPL and trigger extension loading
            # /after/ this package is loaded.
            @async (sleep(0.01); Base.require_stdlib(replid))
        end
    end
end

end
