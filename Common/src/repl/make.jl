import InteractiveUtils.edit

const MAKE_DOC = md"""
Create a new data set from existing information

This drops you into a sandbox where you can interactively develop
a script to produce a new data set.

## Usage

    data> make
    data> make new_dataset_name
"""

const MAKE_INFO_BANNER = "\
This is a sandbox where you can interacively develop the
new data set's creation script. Load any packages needed with
@require instead of import or using, but make sure they've been
registered with @addpkg(s) first.

Press ^D to finish. You'll then have an oppotunity to edit the
final generating function, and the expected return type."

function repl_make(input::AbstractString)
    confirm_stack_nonempty() || begin
        printstyled(" i ", color=:cyan, bold=true)
        println("Consider creating a data collection first with 'init'")
        return nothing
    end
    confirm_stack_first_writable() || return nothing

    name = if isempty(input)
        prompt(" Data set name: ")
    else input end

    while ':' in name
        printstyled(" ! ", color=:yellow, bold=true)
        println("Cannot contain ':'")
        name = prompt(" Data set name: ")
    end

    sandbox = create_sandbox()
    delete!(sandbox.modes.julia.keymap_dict, ';') # Remove shell mode
    println("\e[2m\n", join("  " .* split(MAKE_INFO_BANNER, '\n'), '\n'), "\e[0m\n")

    # Drop the user into the REPL
    previous_repl_module = REPL.active_module()
    try
        REPL.activate(sandbox.mod)
        run_sandbox_repl(sandbox)

        print("\e[F\e[2K") # Remove the last "julia>" prompt line

        if isempty(sandbox.modes.julia.hist.history)
            printstyled("Did nothing\n", color=:light_black)
            return
        end

        (; scriptfn, datavars) = sandbox_to_function(sandbox)
        scriptfile = string(tempname(), ".jl")
        write(scriptfile, string(scriptfn))

        if confirm_yn(" Would you like to edit the final script?", true)
            edit(scriptfile)
        end

        returntype = prompt(" What is the type of the returned value? ",
                            string(QualifiedType(sandbox.lasttype[]))) |> String

        collection = first(STACK)
        dataset = sandbox_dataset(; collection, name, returntype, datavars,
                                scriptfn=read(scriptfile, String))

        push!(collection.datasets, dataset)
        write(collection)
        printstyled(" ✓ Created '$name' ($(dataset.uuid))\n ", color=:green)
    finally
        REPL.activate(previous_repl_module)
    end
end

function create_sandbox()
    mod = Module(:Scratch)

    isdefined(Main, Symbol("@import")) &&
        Core.eval(mod,
                Expr(:toplevel,
                    quote
                        macro __localimport(args...)
                            # This seems hacky, but it also seems to work...
                            Base.macroexpand(Main,
                                             Expr(:macrocall, Symbol("@import"), (),
                                                  args...)) |> esc
                        end
                        const var"@import" = var"@__localimport"
                    end))
    isdefined(Main, :dataset) &&
        Core.eval(mod, Expr(:toplevel, :(const dataset = $(Main.dataset))))
    isdefined(Main, Symbol("@d_str")) &&
        Core.eval(mod, Expr(:toplevel, :(const var"@d_str" = $(Main.var"@d_str"))))

    term_env = get(ENV, "TERM", @static Sys.iswindows() ? "" : "dumb")
    term = REPL.Terminals.TTYTerminal(term_env, stdin, stdout, stderr)
    repl = REPL.LineEditREPL(term, get(stdout, :color, false), true)
    if repl.hascolor
        repl.prompt_color = DataToolkitBase.REPL_PROMPTSTYLE
    end

    repl.interface = REPL.setup_interface(repl)
    julia_mode, shell_mode, help_mode, hist_mode, _ = repl.interface.modes

    julia_mode.prompt = "(data) julia> "
    help_mode.prompt = "(data) help?> "

    hist_ignore = Int[]
    lasttype = Ref(Any)

    # Run in `mod`, not `Main`, and do some input checking.
    julia_mode.on_done = REPL.respond(
        function (line)
            expr = Base.parse_input_line(line, filename=REPL.repl_filename(repl, hist_mode.hp))
            if expr isa Expr && expr.head == :toplevel
                expr = expr.args[2]
            end
            result = if !(expr isa Expr)
                res = Core.eval(mod, expr)
                lasttype[] = typeof(res)
                Expr(:quote, res)
            elseif expr.head ∈ (:const, :global)
                printstyled("ERROR: ", color=:light_red, bold=true)
                println("Disallowed: Global assignment is not permitted")
            elseif expr.head ∈ (:import, :using)
                printstyled("ERROR: ", color=:light_red, bold=true)
                println("Dissalowed: Use @require instead of $(expr.head)")
            elseif expr == :(exit())
                @info "Press ^D to exit"
            else
                try
                    res = Core.eval(mod, expr)
                    if res isa DataToolkitBase.PkgRequiredRerunNeeded
                        res = Core.eval(mod, expr)
                    end
                    lasttype[] = typeof(res)
                    return Expr(:quote, res)
                catch err
                    push!(hist_ignore, length(julia_mode.hist.history))
                    rethrow()
                end
            end
            push!(hist_ignore, length(julia_mode.hist.history))
            result
        end,
        repl,
        julia_mode)

    (; repl, hist_ignore, lasttype, mod,
     modes = ( julia=julia_mode, shell=shell_mode, help=help_mode, hist=hist_mode))
end

@static if VERSION >= v"1.9" # when `MIState.active_module` was added
    # Because `REPL.LineEdit.init_state` is hardcoded to set the module
    # to `Main` we have to copy+tweak `run_repl`, `run_frontend`, and `init_state`.
    # This is horibly icky and I don't like it one bit.
    function run_sandbox_repl(sandbox)
        function run_frontend(repl::REPL.LineEditREPL, backend::REPL.REPLBackendRef)
            repl.frontend_task = current_task()
            d = REPL.REPLDisplay(repl)
            dopushdisplay = repl.specialdisplay === nothing && !in(d, Base.Multimedia.displays)
            dopushdisplay && pushdisplay(d)
            if !isdefined(repl, :interface)
                interface = repl.interface = REPL.setup_interface(repl)
            else
                interface = repl.interface
            end
            repl.backendref = backend
            repl.mistate = REPL.LineEdit.init_state(REPL.terminal(repl), interface)
            # NOTE this is the key line that necessitates all this copypasta
            repl.mistate.active_module = sandbox.mod
            # ^^^ key line
            REPL.run_interface(REPL.terminal(repl), interface, repl.mistate)
            put!(backend.repl_channel, (nothing, -1))
            dopushdisplay && popdisplay(d)
            nothing
        end
        backend = REPL.REPLBackend()
        backend_ref = REPL.REPLBackendRef(backend)
        cleanup = @task try
            REPL.destroy(backend_ref, t)
        catch e
            Core.print(Core.stderr, "\nINTERNAL ERROR: ")
            Core.println(Core.stderr, e)
            Core.println(Core.stderr, catch_backtrace())
        end
        get_module = () -> sandbox.mod
        t = @async run_frontend(sandbox.repl, backend_ref)
        errormonitor(t)
        Base._wait2(t, cleanup)
        REPL.start_repl_backend(backend, _ -> nothing; get_module)
        return backend
    end
else
    const run_sandbox_repl = REPL.run_repl
end

function sandbox_to_function(sandbox)
    validhist = setdiff(axes(sandbox.modes.julia.hist.history, 1), sandbox.hist_ignore)
    # Ensure the last value (i.e. return value) is part of the record.
    if !isempty(validhist) && validhist[end] != length(sandbox.modes.julia.hist.history)
        push!(validhist, length(sandbox.modes.julia.hist.history))
    end
    histlines = sandbox.modes.julia.hist.history[validhist]
    histmodes = sandbox.modes.julia.hist.modes[validhist]

    script = string("begin\n",
                    join(
                        Iterators.map(
                            first,
                            Iterators.filter(
                                ((_line, mode),) -> mode == :julia,
                                zip(histlines, histmodes))),
                        '\n'),
                    "\nend") |> Meta.parse
    first(script.args) isa LineNumberNode &&
        deleteat!(script.args, 1)

    # Collect and organise results

    datavars = extract_datarefs!(script)
    scriptfn = let args = if isempty(datavars)
        Expr(:tuple) else
        Expr(:tuple, Expr(:parameters, first.(datavars)...)) end
        if length(script.args) == 1 && length(args.args) <= 2
            Expr(:->, args, first(script.args))
        else
            Expr(:function, args, script)
        end
    end

    (; scriptfn, datavars)
end

function sandbox_dataset(; collection::DataCollection=first(STACK),
                         spec = prompt_attributes(), name,
                         returntype::String, scriptfn::String,
                         datavars::Vector{<:NamedTuple})
    spec["uuid"] = uuid4()
    spec["loader"] = [Dict{String, Any}("driver" => "julia",
                                        "type" => returntype)]
    dataset = @advise fromspec(DataSet, collection, String(name), spec)
    loader = first(dataset.loaders)

    if !isempty(datavars)
        args = SmallDict{String, Any}()
        for (; var, identstr, type) in datavars
            ident = @advise collection parse(Identifier, identstr)
            if isnothing(type)
            elseif type === :Any && isnothing(ident.type)
                # Resolve `ident` then get the type the same way
                # `read(dataset(...))` does.
                refdataset = resolve(collection, ident, resolvetype=false)
                as = nothing
                for qtype in getproperty.(refdataset.loaders, :type) |> Iterators.flatten
                    as = typeify(qtype, mod=refdataset.collection.mod)
                    isnothing(as) || break
                end
                # Use the picked type, if possible, else fall back on `Any`.
                ident = Identifier(ident.collection, ident.dataset,
                                   QualifiedType(something(as, Any)),
                                   ident.parameters)
            else
                dtype = parse(QualifiedType, string(type))
                ident = Identifier(ident.collection, ident.dataset,
                                   dtype, ident.parameters)
            end
            args[String(var)] = ident
        end
        loader.parameters["arguments"] = args
    end

    savefile = nothing
    if prompt_char(" Should the script be inserted inline (i), or as a file (f)? ",
                              ['i', 'f']) == 'f'
        savefile = prompt(" Save file: ", string(name, ".jl"))
        while isfile(savefile) && !confirm_yn(" File already exists, overwrite?", false)
            savefile = prompt(" Save file: ", string(name, ".jl"))
        end
    end

    if isnothing(savefile)
        loader.parameters["function"] = scriptfn
    else
        loader.parameters["path"] = savefile
        fullpath = abspath(dirname(collection.path),
                           expanduser(get(loader, "pathroot", "")),
                           expanduser(savefile))
        open(fullpath, "w") do io
            timestamp = Dates.format(now(), dateformat"yyyy-mm-ddTH:M:S")
            write(io, "# Generated by $(@__MODULE__)'s \"make\" command $timestamp\n")
            write(io, scriptfn)
        end
    end

    dataset
end

function extract_datarefs!(script::Expr)
    datavars = NamedTuple{(:var, :identstr, :type),
                          Tuple{Symbol, String, Union{Symbol, Expr, Nothing}}}[]

    function datavar!(identstr::String, type::Union{Symbol, Expr, Nothing}=:Any)
        var = if type == :Any
            Symbol(string("data#", identstr))
        else
            Symbol(string("data#", identstr, "::", type))
        end
        if (; var, identstr, type) ∉ datavars
            push!(datavars, (; var, identstr, type))
        end
        var
    end

    function rewrite!(expr::Expr)
        if expr.head ∈ (:invoke, :block, :let, :if, :while, :for, :ref)
            expr.args = rewrite!.(expr.args)
            filter!(!isnothing, expr.args)
        elseif expr.head == :(=)
            expr.args[2] = rewrite!(expr.args[2])
        elseif expr.head ∈ (:const, :global) # no global bindings allowed
            first(expr.args)
        elseif expr.head == :macrocall
            if first(expr.args) == Symbol("@d_str")
                return datavar!(expr.args[3])
            else
                expr.args = rewrite!.(expr.args)
            end
        elseif expr.head == :call
            if first(expr.args) == :read && length(expr.args) > 1 &&
                expr.args[2] isa Expr && expr.args[2].head == :call &&
                first(expr.args[2].args) == :dataset
                # Case: read(dataset(...), ...)
                if length(expr.args[2].args) == 2 && expr.args[2].args[2] isa String
                    type = if length(expr.args) == 2
                        :Any else expr.args[3] end
                    identstr = expr.args[2].args[2]
                    return datavar!(identstr, type)
                else
                    @warn "Unsupported data form: $expr"
                end
            elseif first(expr.args) == :dataset && length(expr.args) == 2
                # Case: dataset(...)
                return datavar!(expr.args[2], nothing)
            else
                expr.args = rewrite!.(expr.args)
            end
        end
        expr
    end
    rewrite!(::LineNumberNode) = nothing
    rewrite!(x::Any) = x

    rewrite!(script)
    datavars
end
