module REPLcmds

using REPL, REPL.TerminalMenus

using DataToolkitBase
using TOML
using UUIDs

import DataToolkitBase: REPL_CMDS, ReplCmd, completions, allcompletions,
    prompt, prompt_char, confirm_yn, peelword, displaytable, natkeygen,
    REPL_QUESTION_COLOR, REPL_USER_INPUT_COLOUR

include("utils.jl")

include("init.jl")
include("stack.jl")
include("plugins.jl")
include("config.jl")
include("create.jl")
include("delete.jl")
include("list.jl")
include("show.jl")

function add_repl_cmds()
    push!(REPL_CMDS,
          ReplCmd(:init, INIT_DOC, init))

    push!(REPL_CMDS,
          ReplCmd(:stack,
                  "Operate on the data collection stack",
                  STACK_SUBCOMMANDS))

    push!(REPL_CMDS,
      ReplCmd(:plugin,
              "Inspect and modify the set of plugins used

Call without any arguments to see the availible subcommands.",
              PLUGIN_SUBCOMMANDS))

    push!(REPL_CMDS,
          ReplCmd(:config,
                  "Inspect and modify the current configuration",
                  CONFIG_SUBCOMMANDS))

    push!(REPL_CMDS,
          ReplCmd(:create, CREATE_DOC, create))

    push!(REPL_CMDS,
          ReplCmd(:delete, DELETE_DOC, delete))

    push!(REPL_CMDS,
          ReplCmd(:list,
                  "List the datasets in a certain collection

By default, the datasets of the active collection are shown.",
                  repl_list))

    push!(REPL_CMDS,
          ReplCmd(:show,
                  "List the dataset refered to by an identifier",
                  repl_show))
end

end
