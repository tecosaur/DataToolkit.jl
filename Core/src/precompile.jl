@setup_workload begin
    datatoml = """
    data_config_version = 0
    uuid = "84068d44-24db-4e28-b693-58d2e1f59d05"
    name = "precompile"
    plugins = []

    [[dataset]]
    uuid = "d9826666-5049-4051-8d2e-fe306c20802c"
    self = "$(DATASET_REFERENCE_WRAPPER[1])dataset$(DATASET_REFERENCE_WRAPPER[2])"
    other = {a = [1, 2], b = [3, 4]}

        [[dataset.storage]]
            driver = "raw"
            value = 3
            type = "Int"

        [[dataset.loader]]
            driver = "passthrough"
            type = "Int"
    """
    # function getstorage(storage::DataStorage{:raw}, T::Type)
    #     get(storage, "value", nothing)::Union{T, Nothing}
    # end
    # function load(::DataLoader{:passthrough}, from::T, ::Type{T}) where {T <: Any}
    #     from
    # end
    if VERSION >= v"1.9"
        Base.active_repl =
            REPL.LineEditREPL(REPL.Terminals.TTYTerminal("", stdin, stdout, stderr), true)
    end
    @compile_workload begin
        loadcollection!(IOBuffer(datatoml))
        write(devnull, STACK[1])
        dataset("dataset")
        # read(dataset("dataset"))
        sprint(show, STACK[1], context = :color => true)
        sprint(show, dataset("dataset"), context = :color => true)
        lint(STACK[1])
        @advise STACK[1] sum(1:3)
        # REPL
        if VERSION >= v"1.9"
            init_repl()
            redirect_stdio(stdout=devnull, stderr=devnull) do
                toplevel_execute_repl_cmd("?")
                toplevel_execute_repl_cmd("?help")
                toplevel_execute_repl_cmd("help help")
                toplevel_execute_repl_cmd("help :")
            end
        end
        complete_repl_cmd("help ")
        # Other stuff
        get(dataset("dataset"), "self")
        get(dataset("dataset"), "other")
    end
    # Base.delete_method(first(methods(getstorage, Tuple{DataStorage{:raw}, Type}).ms))
    # Base.delete_method(first(methods(load, Tuple{DataLoader{:passthrough}, Any, Any}).ms))
    empty!(STACK)
end
