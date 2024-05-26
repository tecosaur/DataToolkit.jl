module REPLCmds

using REPL, REPL.TerminalMenus
import InteractiveUtils.edit

using DataToolkitBase
using Dates
using Markdown
using TOML
using UUIDs

import DataToolkitBase: REPL_CMDS, ReplCmd, add_repl_cmd!,
    prompt, prompt_char, confirm_yn, peelword, displaytable, natkeygen,
    REPL_QUESTION_COLOR, REPL_USER_INPUT_COLOUR

import DataToolkitCommon.show_extra

include("utils.jl")

include("init.jl")
include("stack.jl")
include("plugins.jl")
include("config.jl")
include("add.jl")
include("remove.jl")
include("list.jl")
include("show.jl")
include("search.jl")
include("lint.jl")
include("make.jl")
include("edit.jl")

function __init__()
    new_cmds = ReplCmd[
        ReplCmd("add",    ADD_DOC,    add),
        ReplCmd("init",   INIT_DOC,   init),
        ReplCmd("config", CONFIG_DOC, CONFIG_SUBCOMMANDS),
        ReplCmd("check",  CHECK_DOC,  repl_lint,  complete_dataset_or_collection),
        ReplCmd("edit",   EDIT_DOC,   repl_edit,  complete_dataset),
        ReplCmd("list",   LIST_DOC,   repl_list,  complete_collection),
        ReplCmd("make",   MAKE_DOC,   repl_make),
        ReplCmd("plugin", PLUGIN_DOC, PLUGIN_SUBCOMMANDS),
        ReplCmd("remove", REMOVE_DOC, remove,     complete_dataset),
        ReplCmd("search", SEARCH_DOC, search),
        ReplCmd("show",   SHOW_DOC,   repl_show,  complete_dataset),
        ReplCmd("stack",  STACK_DOC,  STACK_SUBCOMMANDS)]
    foreach(add_repl_cmd!, new_cmds)
end

include("precompile.jl")

end
