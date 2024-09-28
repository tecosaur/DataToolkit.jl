module REPLDocHelpers

using DataToolkitCore
using DataToolkitREPL

using Documenter: Documenter, Selectors, Expanders.ExpanderPipeline, Expanders.TrackHeaders
using Documenter.MarkdownAST: MarkdownAST, Node, insert_before!, unlink!

using Markdown

function datarepl(cmd::String)
    pipe = Pipe()
    started = Base.Event()
    writer = @async redirect_stdio(stdout=pipe, stderr=pipe) do
        notify(started)
        DataToolkitREPL.execute_repl_cmd(cmd)
        close(Base.pipe_writer(pipe))
    end
    wait(started)
    result = read(pipe, String)
    wait(writer)
    Node(MarkdownAST.CodeBlock(
        "text", replace(result, r"\e\[[^m]*m" => "", r"^\t" => "")))
end

function datareplhelp(cmd::String; postrule::Bool=true)
    repl_cmd = DataToolkitREPL.find_repl_cmd(first(eachsplit(cmd, ' ')))
    for subcmd in last(Iterators.peel(eachsplit(cmd, ' ')))
        repl_cmd = DataToolkitREPL.find_repl_cmd(subcmd, commands = repl_cmd.execute)
    end
    header = Markdown.Header{2}([Markdown.Code("?$cmd")])
    desc = if repl_cmd.description isa Markdown.MD
        mdreformat(h::Markdown.Header{n}) where {n} = Markdown.Header{n+2}(h.text)
        mdreformat(md::Any) = md
        Markdown.MD(map(mdreformat, repl_cmd.description.content))
    else
        Markdown.MD(Markdown.Code("text", string(repl_cmd.description)))
    end
    convert(Node, desc)
end

abstract type DataREPLBlocks <: ExpanderPipeline end
abstract type DataREPLHelpBlocks <: ExpanderPipeline end

Selectors.order(::Type{DataREPLBlocks}) = 3.5
Selectors.order(::Type{DataREPLHelpBlocks}) = 4.5

Selectors.matcher(::Type{DataREPLBlocks}, node, page, doc) = Documenter.iscode(node, "@datarepl")
Selectors.matcher(::Type{DataREPLHelpBlocks}, node, page, doc) = Documenter.iscode(node, "@datareplhelp")

function Selectors.runner(::Type{DataREPLBlocks}, node, page, doc)
    @assert node.element isa MarkdownAST.CodeBlock
    for line in eachsplit(node.element.code, '\n')
        res = datarepl(String(line))
        heading = Node(MarkdownAST.Heading(2))
        push!(heading.children, Node(MarkdownAST.Code(line)))
        insert_before!(node, heading)
        Selectors.runner(TrackHeaders, heading, page, doc)
        insert_before!(node, res)
    end
    unlink!(node)
end

function Selectors.runner(::Type{DataREPLHelpBlocks}, node, page, doc)
    @assert node.element isa MarkdownAST.CodeBlock
    for line in eachsplit(node.element.code, '\n')
        resnode = datareplhelp(String(line))
        heading = MarkdownAST.@ast MarkdownAST.Heading(2) do
            MarkdownAST.Link("@id repl-" * replace(line, ' ' => '-'), "") do
                MarkdownAST.Code('?' * line)
            end
        end
        insert_before!(node, heading)
        Selectors.runner(TrackHeaders, heading, page, doc)
        for child in resnode.children
            child = MarkdownAST.copy_tree(child)
            insert_before!(node, child)
            if child.element isa MarkdownAST.Heading
                Selectors.runner(TrackHeaders, child, page, doc)
            end
        end
    end
    unlink!(node)
end

end
