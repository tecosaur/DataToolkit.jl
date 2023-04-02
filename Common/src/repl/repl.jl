module REPLcmds

using REPL, REPL.TerminalMenus

using DataToolkitBase
using TOML
using UUIDs
using Dates

import DataToolkitBase: REPL_CMDS, ReplCmd, completions, allcompletions,
    prompt, prompt_char, confirm_yn, peelword, displaytable, natkeygen,
    REPL_QUESTION_COLOR, REPL_USER_INPUT_COLOUR

include("utils.jl")

include("init.jl")
include("stack.jl")
include("plugins.jl")
include("config.jl")
include("add.jl")
include("delete.jl")
include("list.jl")
include("show.jl")
include("search.jl")
include("make.jl")

function add_repl_cmds()
    push!(REPL_CMDS,
          ReplCmd(:add, ADD_DOC, add),
          ReplCmd(:delete, DELETE_DOC, delete),
          ReplCmd(:init, INIT_DOC, init),
          ReplCmd(:config,
                  "Inspect and modify the current configuration",
                  CONFIG_SUBCOMMANDS),
          ReplCmd(:list,
                  "List the datasets in a certain collection

By default, the datasets of the active collection are shown.",
                  repl_list),
          ReplCmd(:make,
                  MAKE_DOC,
                  repl_make),
          ReplCmd(:plugin,
                  "Inspect and modify the set of plugins used

Call without any arguments to see the availible subcommands.",
                  PLUGIN_SUBCOMMANDS),
          ReplCmd(:search,
                  "Search for a particular data collection",
                  search),
          ReplCmd(:show,
                  "List the dataset refered to by an identifier",
                  repl_show),
          ReplCmd(:stack,
                  "Operate on the data collection stack",
                  STACK_SUBCOMMANDS))
end

end
