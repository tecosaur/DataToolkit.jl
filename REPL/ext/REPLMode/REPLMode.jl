module REPLMode

using REPL, REPL.LineEdit, REPL.TerminalMenus
using InteractiveUtils: edit

using Dates
using Markdown
using TOML
using UUIDs

using DataToolkitCore
using DataToolkitCore: STACK, TRANSFORMER_DOCUMENTATION, issubseq,
    getlayer, highlight_lcs, stringsimilarity, natkeygen, trycreateauto

using DataToolkitREPL: ReplCmd, REPL_KEY, REPL_NAME, REPL_PROMPT,
    REPL_PROMPTSTYLE, REPL_QUESTION_COLOR, REPL_USER_INPUT_COLOUR, REPL_CMDS,
    add_repl_cmd!

import DataToolkitREPL: help, find_repl_cmd, execute_repl_cmd,
    complete_repl_cmd, init_repl, prompt, prompt_char, confirm_yn, peelword,
    show_extra, displaytable, help_cmd_table, help_show, transformer_docs,
    transformers_printall

include("utils.jl")
include("help.jl")
include("setup.jl")

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

include("lint_rules.jl")

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
    isinteractive() || return
    if isdefined(Base, :active_repl)
        init_repl(Base.active_repl)
    else
        atreplinit() do repl
            if isinteractive() && repl isa REPL.LineEditREPL
                isdefined(repl, :interface) ||
                    (repl.interface = REPL.setup_interface(repl))
                init_repl(repl)
            end
        end
    end
end

include("precompile.jl")

end
