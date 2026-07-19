using DataToolkitCore
using Test

import DataToolkitCore: natkeygen, stringdist, stringsimilarity,
    longest_common_subsequence, highlight_lcs, referenced_datasets,
    stack_index, plugin_add!, plugin_list, plugin_remove!, config_get,
    config_set!, config_unset!, reinit!, DATASET_REFERENCE_WRAPPER,
    ispreferredpath, DataLoader, DataStorage, DataWriter, DataTransformer,
    trycreateauto, createinteractive, getstorage, load, supportedtypes,
    typesteps, toml_safe, refresh!, save!, flushpendingwrites, iswritable,
    WRITE_RECORDS, WriteRecord

@testset "Utils" begin
    @testset "Doctests" begin
        @test natkeygen.(["A1", "A10", "A02", "A1.5"]) ==
            [["a", "0\x011"], ["a", "0\x0210"], ["a", "0\x012"], ["a", "0\x0115"]]
        @test sort(["A1", "A10", "A02", "A1.5"], by=natkeygen) ==
            ["A1", "A1.5", "A02", "A10"]
        @test natkeygen("x" * "9"^30) == ["x", '0' * Char(30) * "9"^30]
        @test sort(["a1", "a10", "a2", "run20260717120000"], by=natkeygen) ==
            ["a1", "a2", "a10", "run20260717120000"]
        @test stringdist("The quick brown fox jumps over the lazy dog",
                        "The quack borwn fox leaps ovver the lzy dog") == 7
        @test stringdist("typo", "tpyo") == 1
        @test stringdist("frog", "cat") == 4
        @test stringsimilarity("same", "same") == 1.0
        @test stringsimilarity("semi", "demi") == 0.75
        @test longest_common_subsequence("same", "same") == [1:4;]
        @test longest_common_subsequence("fooandbar", "foobar") == vcat(1:3, 7:9)
    end
    @testset "Multi-codepoint unicode" begin
        @test stringdist("ÆaÆb", "ÆacÆb") == 1
        @test stringsimilarity("ÆaÆb", "ÆacÆb") == 0.8
        @test longest_common_subsequence("heyÆsop", "hiÆsop") == vcat(1, 4:7)
    end
    @testset "Highlighting LCS" begin
        io = IOContext(IOBuffer(), :color => true)
        highlight_lcs(io, "hey", "hey")
        @test String(take!(io.io)) == "\e[1mhey\e[22m"
        highlight_lcs(io, "hey", "hey", invert=true)
        @test String(take!(io.io)) == "hey\e[22m"
        highlight_lcs(io, "hey", "hey", before="^", after="_")
        @test String(take!(io.io)) == "^hey_"
        highlight_lcs(io, "xxheyyy", "aaheybb")
        @test String(take!(io.io)) == "xx\e[1mhey\e[22myy\e[22m"
        highlight_lcs(io, "xxheyyy", "aaheybb", before="^", after="_", invert=true)
        @test String(take!(io.io)) == "^xx_hey^yy_"
        highlight_lcs(io, "xxheyyy", "xx___yy")
        @test String(take!(io.io)) == "\e[1mxx\e[22mhey\e[1myy\e[22m"
        highlight_lcs(io, "abc", "xyz")
        @test String(take!(io.io)) == "abc"
    end
end

@testset "Advice" begin
    # Some advice to use
    sump1 = Advice(2, (f::typeof(sum), i::Int) -> (f, (i+1,)))
    sump1a = Advice(2, (f::typeof(sum), i::Int) -> (f, (i+1,), (;)))
    sump1b = Advice(2, (f::typeof(sum), i::Int) -> (identity, f, (i+1,)))
    sump1c = Advice(2, (f::typeof(sum), i::Int) -> (identity, f, (i+1,), (;)))
    sump1x = Advice(2, (f::typeof(sum), i::Int) -> ())
    sumx2 = Advice(1, (f::typeof(sum), i::Int) -> (f, (2*i,)))
    summ3 = Advice(1, (f::typeof(sum), i::Int) -> (x -> x-3, f, (i,)))
    @testset "Basic advice" begin
        # Application of advice
        @test sump1((identity, sum, (1,), (;))) ==
            (identity, sum, (2,), (;))
        @test sump1(sum, 1) == 2
        @test sump1a(sum, 1) == 2
        @test sump1b(sum, 1) == 2
        @test sump1c(sum, 1) == 2
        @test_throws ErrorException sump1x(sum, 1) == 2
        # Pass-through of `post`
        @test sump1((sqrt, sum, (1,), (;))) ==
            (sqrt, sum, (2,), (;))
        # Matching the argument
        @test sump1((identity, sum, ([1],), (;))) ==
            (identity, sum, ([1],), (;))
        @test sump1(sum, [1]) == 1
        # Matching the kwargs
        @test sump1((identity, sum, (1,), (dims=3,))) ==
            (identity, sum, (1,), (dims = 3,))
        # Matching the function
        @test sump1((identity, sqrt, (1,), (;))) ==
            (identity, sqrt, (1,), (;))
        let # Using invokelatest on the advice function
            thing(x) = x^2
            h(x) = x+1
            thing_a = Advice((f::typeof(thing), i::Int) -> (f, (h(i),)))
            @test thing_a((identity, thing, (2,), (;))) ==
                (identity, thing, (3,), (;))
            h(x) = x+2
            @test thing_a((identity, thing, (2,), (;))) ==
                (identity, thing, (4,), (;))
        end
    end
    @testset "Amalgamation" begin
        amlg12 = AdviceAmalgamation([sumx2, sump1], String[], String[])
        @test amlg12.advisors == AdviceAmalgamation([sumx2, sump1]).advisors
        @test AdviceAmalgamation(amlg12).advisors == Advice[] # no plugins
        amlg21 = AdviceAmalgamation([sump1, sumx2], String[], String[])
        amlg321 = AdviceAmalgamation([sump1, sumx2, summ3], String[], String[])
        amlg213 = AdviceAmalgamation([summ3, sump1, sumx2], String[], String[])
        @test amlg12((identity, sum, (2,), (;))) == (identity, sum, (5,), (;))
        @test amlg12(sum, 2) == 5
        @test amlg21(sum, 2) == 6
        @test amlg321(sum, 2) == 3
        @test amlg213(sum, 2) == 3
    end
    @testset "Plugin loading" begin
        # Empty state
        amlg = empty(AdviceAmalgamation)
        @test amlg.advisors == Advice[]
        @test amlg.plugins_wanted == String[]
        @test amlg.plugins_used == String[]
        # Create a plugin
        plg = Plugin(string(gensym()), [sump1, sumx2])
        push!(PLUGINS, plg)
        @test Plugin("", [sumx2.f]).advisors == Plugin("", [sumx2]).advisors
        # Desire the plugin, then check the advice is incorperated correctly
        push!(amlg.plugins_wanted, plg.name)
        @test amlg(identity, 1) == 1 # Should call `reinit`
        @test amlg.advisors == [sumx2, sump1]
        @test amlg.plugins_wanted == [plg.name]
        @test amlg.plugins_used == [plg.name]
        @test reinit!(AdviceAmalgamation(amlg)).advisors == amlg.advisors
        let cltn = DataCollection()
            push!(cltn.plugins, plg.name)
            @test reinit!(AdviceAmalgamation(cltn)).advisors == amlg.advisors
        end
        # Display
        @test sprint(show, amlg) == "AdviceAmalgamation($(plg.name) ✔)"
    end
    @testset "Advice macro" begin
        @test :($(GlobalRef(DataToolkitCore, :_dataadvisecall))(func, x)) ==
            @macroexpand @advise func(x)
        @test :($(GlobalRef(DataToolkitCore, :_dataadvisecall))(func, x, y, z)) ==
            @macroexpand @advise func(x, y, z)
        @test :($(GlobalRef(DataToolkitCore, :_dataadvisecall))(func; a=1, b)) ==
            @macroexpand @advise func(; a=1, b)
        @test :($(GlobalRef(DataToolkitCore, :_dataadvisecall))(func, x, y, z; a=1, b)) ==
            @macroexpand @advise func(x, y, z; a=1, b)
        @test :($(GlobalRef(DataToolkitCore, :_dataadvisecall))($(GlobalRef(DataToolkitCore, :Val)){:noassert}(), func, x, y, z; a=1, b)::Int) ==
            @macroexpand @advise func(x, y, z; a=1, b)::Int
        @test :(($(GlobalRef(DataToolkitCore, :_dataadvise))(a, func, x))) ==
            @macroexpand @advise a func(x)
        @test :(($(GlobalRef(DataToolkitCore, :_dataadvise))(a))(func, x)::Int) ==
            @macroexpand @advise a func(x)::Int
        @test :(($(GlobalRef(DataToolkitCore, :_dataadvise))(source(a), func, x))) ==
            @macroexpand @advise source(a) func(x)
        @test_throws LoadError eval(:(@advise (1, 2)))
        @test_throws LoadError eval(:(@advise f()))
        @test 2 == @advise sump1 sum(1)
        @test 2 == @advise [sump1] sum(1)
        @test 2 == @advise AdviceAmalgamation([sump1]) sum(1)
    end
    deleteat!(PLUGINS, length(PLUGINS)) # remove `plg`
end

@testset "Type path ordering" begin
    L = DataLoader{:l}
    path(from::Type, to::Type, ind) = (Pair{Type, Type}(from, to), ind, L)
    # A lower index wins even against a more specific output, and vice-versa at
    # equal index — the mutual exclusivity the old ||-chain lost.
    @test ispreferredpath(path(IO, Any, 1), path(IO, String, 2))
    @test !ispreferredpath(path(IO, String, 2), path(IO, Any, 1))
    @test ispreferredpath(path(IO, String, 1), path(IO, Any, 1))
    @test !ispreferredpath(path(IO, Any, 1), path(IO, String, 1))
    paths = [path(IO, Any, 2), path(IO, String, 1),
             path(IO, Any, 1), path(IO, Integer, 1)]
    @test !any(Iterators.product(paths, paths)) do (a, b)
        ispreferredpath(a, b) && ispreferredpath(b, a)
    end
    sorted = sort(paths, lt = ispreferredpath, alg = MergeSort)
    @test map(p -> p[2], sorted) == [1, 1, 1, 2]
    @test last(sorted)[1] == (IO => Any)
end

@testset "QualifiedType" begin
    @testset "Construction" begin
        @test QualifiedType(:a, :b) == QualifiedType(:a, :b, ())
        @test QualifiedType(Any) == QualifiedType(:Core, :Any, ())
        @test QualifiedType(Int) == QualifiedType(:Core, nameof(Int), ())
        @test QualifiedType(IO) == QualifiedType(:Core, :IO, ())
        # This test currently fails due to typevar inequivalence
        # @test QualifiedType(QualifiedType) ==
        #     QualifiedType(:DataToolkitCore, :QualifiedType, (TypeVar(:T, Union{}, Tuple),))
        @test QualifiedType(QualifiedType(:a, :b)) == QualifiedType(:a, :b, ())
    end
    @testset "Typeification" begin
        @test trytypeify(QualifiedType(:a, :b)) === nothing
        @test trytypeify(QualifiedType(:Core, :Int)) == Int
        @test trytypeify(QualifiedType(:Core, :IO)) == IO
        @test trytypeify(QualifiedType(:DataToolkitCore, :QualifiedType, ())) == QualifiedType
        @test trytypeify(QualifiedType(:Core, :Array, (QualifiedType(:Core, :Integer, ()), 1))) ==
            Vector{Integer}
        # Test module expansion with unexported type
        @test trytypeify(QualifiedType(:Main, :AnyDict, ())) === nothing
        @test trytypeify(QualifiedType(:Main, :AnyDict, ()), mod=Base) == Base.AnyDict
    end
    @testset "Subtyping" begin
        @test QualifiedType(Int) ⊆ QualifiedType(Integer)
        @test Int ⊆ QualifiedType(Integer)
        @test QualifiedType(Int) ⊆ Integer
        @test !(QualifiedType(Integer) ⊆ QualifiedType(Int))
        @test !(Integer ⊆ QualifiedType(Int))
        @test !(QualifiedType(Integer) ⊆ Int)
        @test !(QualifiedType(:a, :b) ⊆ Integer)
        @test !(Integer ⊆ QualifiedType(:a, :b))
        @test QualifiedType(:a, :b) ⊆ QualifiedType(:a, :b)
        @test !(QualifiedType(:Main, :AnyDict, ()) ⊆ AbstractDict)
        @test ⊆(QualifiedType(:Main, :AnyDict, ()), AbstractDict, mod = Base)
    end
end

import DataToolkitCore: get_package, addpkg

@testset "UsePkg" begin
    @testset "add/get package" begin
        test = Base.PkgId(Base.UUID("8dfed614-e22c-5e08-85e1-65c5234f0b40"), "Test")
        @test get_package(test) === Test
        @test_throws UnregisteredPackage get_package(@__MODULE__, :Test)
        @test addpkg(@__MODULE__, :Test, "8dfed614-e22c-5e08-85e1-65c5234f0b40") isa Any
        @test @addpkg(Test, "8dfed614-e22c-5e08-85e1-65c5234f0b40") isa Any
        @test get_package(@__MODULE__, :Test) === Test
        # A genuinely-absent package still reports as missing.
        absent = Base.PkgId(Base.UUID("00000000-0000-0000-0000-000000000000"), "NoSuchPkg")
        @test_throws MissingPackage get_package(absent)
    end
    @testset "@require" begin
        nolinenum(blk) = Expr(:block, filter(e -> !(e isa LineNumberNode), blk.args)...)
        ref_get_package = GlobalRef(DataToolkitCore, :get_package)
        ref_isa = GlobalRef(DataToolkitCore, :isa)
        pkgrereun = GlobalRef(DataToolkitCore, :PkgRequiredRerunNeeded)
        @test quote
            A = $ref_get_package($Main, :A)
            $ref_isa(A, $pkgrereun) && return A
        end |> nolinenum == nolinenum(@macroexpand @require A)
    end
end

@testset "stringification" begin
    @testset "QualifiedType" begin
        for (str, qt) in [("a.b", QualifiedType(:a, :b)),
                          ("a.b.c", QualifiedType(:a, [:b], :c)),
                          ("a.b.c.d", QualifiedType(:a, [:b, :c], :d)),
                          ("String", QualifiedType(String)),
                          ("a.b{c.d}", QualifiedType(:a, :b, (QualifiedType(:c, :d),))),
                          ("a.b.c{d.e.f}", QualifiedType(:a, [:b], :c, (QualifiedType(:d, [:e], :f),))),
                          ("Matrix{Bool}", QualifiedType(Matrix{Bool})),
                          ("Vector{Vector{Array{<:Integer,1}}}",
                           QualifiedType(Vector{Vector{Vector{<:Integer}}})),
                          ("Ref{I<:Integer}", QualifiedType(Ref{I} where {I <: Integer}))]
            @test str == string(qt)
            # Due to TypeVar comparison issues, instead of
            # the following test, we'll do a round-trip instead.
            # @test parse(QualifiedType, str) == qt
            @test str == string(parse(QualifiedType, str))
        end
    end
    @testset "Identifiers" begin
        for (istr, ident) in [("a", Identifier(nothing, "a", nothing, Dict{String, Any}())),
                              ("a:b", Identifier("a", "b", nothing, Dict{String, Any}())),
                              ("a::Main.sometype", Identifier(nothing, "a", QualifiedType(:Main, :sometype), Dict{String, Any}())),
                              ("a:b::Bool", Identifier("a", "b", QualifiedType(:Core, :Bool), Dict{String, Any}())),
                              # Non-ASCII around the colon must not BoundsError on byte indexing.
                              ("café:δ", Identifier("café", "δ", nothing, Dict{String, Any}()))]
            @test parse_ident(istr) == ident
            @test istr == string(ident)
        end
        # A trailing colon after non-ASCII must parse (not BoundsError) as an
        # empty dataset in that collection.
        @test parse_ident("α:") == Identifier("α", "", nothing, Dict{String, Any}())
    end
end

@testset "DataSet Parameters" begin
    refpre, refpost = DATASET_REFERENCE_WRAPPER
    datatoml = """
    data_config_version = 0
    uuid = "1c59ad24-f655-4903-b791-f3ef3afc5df1"
    name = "datatest"

    config.ref = "$(refpre)adataset$(refpost)"

    [[adataset]]
    uuid = "8c12e6b4-6987-44e9-a33d-efe2ad60f501"
    self = "$(refpre)adataset$(refpost)"
    others = { b = "$(refpre)bdataset$(refpost)" }

    [[bdataset]]
    uuid = "aa5ba7ab-cabd-4c08-8e4e-78d516e15801"
    other = ["$(refpre)adataset$(refpost)"]
    """
    collection = read(IOBuffer(datatoml), DataCollection)
    adataset, bdataset = sort(collection.datasets, by=d -> d.name)
    @test Set(referenced_datasets(adataset)) == Set([adataset, bdataset])
    @test referenced_datasets(bdataset) == [adataset]
    @test get(adataset, "self") == adataset
    @test adataset == @getparam adataset."self"
    @test get(adataset, "others")["b"] == bdataset
    @test get(bdataset, "other") == [adataset]
    # Collection config cannot hold data set refs
    @test get(collection, "ref") == "$(refpre)adataset$(refpost)"
end

@testset "LogTaskError display" begin
    # Displaying a LogTaskError must surface the inner exception, not crash in
    # the stacktrace-simplifying filter! (which used to index `.file` on a raw
    # backtrace pointer → FieldError, masking every @log_do failure).
    failed = @task error("inner boom")
    schedule(failed)
    try wait(failed) catch end
    lte = DataToolkitCore.LogTaskError(failed)
    rawbt = try error("outer") catch; catch_backtrace() end
    old = DataToolkitCore.SIMPLIFY_STACKTRACES[]
    try
        DataToolkitCore.SIMPLIFY_STACKTRACES[] = true
        # `bt` arrives raw from `throw`, or already resolved from a nested
        # `showerror`; both must render the inner error, not crash.
        for bt in (rawbt, stacktrace(rawbt))
            rendered = sprint((io, e) -> showerror(io, e, bt), lte)
            @test occursin("inner boom", rendered)
            @test !occursin("has no field", rendered)
            @test !occursin("no method matching stacktrace", rendered)
        end
    finally
        DataToolkitCore.SIMPLIFY_STACKTRACES[] = old
    end
end

# Test-local transformer methods for the type-dispatch and construction tests
# below. New driver symbols (`:mem`, `:idl`, `:pick`) are used so as not to
# perturb the `:raw`/`:passthrough` methods the "Dry run" testset relies on.
# `PROBE` records which `load` method fired, the integration-observable signal
# that read1 walked the intended type path.
const PROBE = String[]
@eval begin
    getstorage(s::DataStorage{:mem}, ::Type{Vector{Int}}) =
        get(s, "value", nothing)::Union{Vector{Int}, Nothing}
    supportedtypes(::Type{DataStorage{:mem}}, ::Dict{String, Any}) =
        [QualifiedType(Vector{Int})]
    load(::DataLoader{:idl}, x::Vector{Int}, ::Type{T}) where {T} = x
    supportedtypes(::Type{DataLoader{:idl}}, ::Dict{String, Any}, ds::DataSet) =
        reduce(vcat, getproperty.(ds.storage, :type)) |> unique
    # Two `:pick` load methods differing only by output specificity — the case
    # ispreferredpath must disambiguate (Vector{Int} beats Any).
    function load(::DataLoader{:pick}, x::Vector{Int}, ::Type{Any})
        push!(PROBE, "any"); x
    end
    function load(::DataLoader{:pick}, x::Vector{Int}, ::Type{Vector{Int}})
        push!(PROBE, "vecint"); x .+ 100
    end
    supportedtypes(::Type{DataLoader{:pick}}, ::Dict{String, Any}, ds::DataSet) =
        reduce(vcat, getproperty.(ds.storage, :type)) |> unique
end

# Build a probe DataSet off-STACK with `:mem` storage and the given loader driver.
function probe_dataset(loaderdriver::Symbol)
    dc = DataCollection()
    ds = DataSet(dc, "probe", Dict{String, Any}(
        "uuid" => string(Base.UUID(rand(UInt128)))))
    storage!(ds, :mem, "value" => [1, 2, 3])
    loader!(ds, loaderdriver)
    ds
end

@testset "typesteps resolution" begin
    ds = probe_dataset(:pick)
    loader, storage = ds.loaders[1], ds.storage[1]
    lsteps = typesteps(loader, Vector{Int})
    @test lsteps isa Vector{Pair{Type, Type}}
    @test !isempty(lsteps)
    # The most-specific output wins: the first (and, after dedup, only) step
    # produces Vector{Int}, never Any.
    @test last(first(lsteps)) == Vector{Int}
    @test !any(p -> last(p) == Any, lsteps)
    # Storage in-type is Nothing; it produces the desired Vector{Int}.
    ssteps = typesteps(storage, Vector{Int}; write = false)
    @test (Nothing => Vector{Int}) in ssteps
    # End-to-end: read must fire the specific `Vector{Int}` method (which tags
    # itself "vecint" and offsets by 100), not the `Any` fallback.
    empty!(PROBE)
    @test read(ds, Vector{Int}) == [101, 102, 103]
    @test PROBE == ["vecint"]
    # A desired supertype still resolves through the specific method.
    empty!(PROBE)
    @test read(ds, AbstractVector) == [101, 102, 103]
    @test PROBE == ["vecint"]
    # Public reflection lists both declared output types.
    outs = supportedtypes(DataLoader{:pick})
    @test QualifiedType(Vector{Int}) in outs
    @test QualifiedType(Any) in outs
end

@testset "Programmatic collection construction" begin
    stacklen = length(STACK)
    try
        dc = create!(DataCollection, "built", nothing)
        @test first(STACK) === dc
        @test dc.source === nothing
        @test dc.name == "built"
        ds = dataset!(dc, "d", Dict{String, Any}("k" => 1))
        @test ds in dc.datasets
        @test ds.collection === dc
        @test get(ds, "k") == 1
        @test ds.uuid isa Base.UUID
        # The pair-splat convenience form must accept "k" => v like create! does.
        dp = dataset!(dc, "dp", "a" => 1, "b" => "two")
        @test get(dp, "a") == 1 && get(dp, "b") == "two"
        storage!(ds, :mem, "value" => [1, 2, 3])
        loader!(ds, :idl)
        writer!(ds, :idl)
        @test length(ds.storage) == length(ds.loaders) == length(ds.writers) == 1
        @test DataToolkitCore.driverof(typeof(ds.storage[1])) === :mem
        @test DataToolkitCore.driverof(typeof(ds.loaders[1])) === :idl
        @test ds.storage[1].dataset === ds
        # create! honours a supplied uuid; the plain `create` does not mutate.
        u = string(Base.UUID(rand(UInt128)))
        d2 = create!(dc, DataSet, "d2", Dict{String, Any}("uuid" => u, "x" => 2))
        @test string(d2.uuid) == u
        @test d2 in dc.datasets
        n = length(dc.datasets)
        d3 = create(dc, DataSet, "d3", Dict{String, Any}("x" => 3))
        @test length(dc.datasets) == n
        @test d3 ∉ dc.datasets
        # An abstract/unknown transformer type is rejected; a mismatched
        # driver symbol against a driver-parameterised type is rejected.
        @test_throws ArgumentError create(ds, DataTransformer, Dict{String, Any}())
        @test_throws ArgumentError create!(ds, DataStorage{:mem}, :other, "k" => 1)
        # Structural spec reflects the built transformer.
        spec = convert(Dict, ds)
        @test spec["storage"][1]["driver"] == "mem"
        @test spec["storage"][1]["value"] == [1, 2, 3]
    finally
        while length(STACK) > stacklen
            popfirst!(STACK)
        end
    end
end

@testset "toml_safe coercion" begin
    dc = DataCollection()
    ds = DataSet(dc, "d", Dict{String, Any}(
        "uuid" => string(Base.UUID(rand(UInt128)))))
    @test toml_safe(QualifiedType(Int)) == "Int64"
    @test toml_safe(Int) == "Int64"
    @test toml_safe(42) === 42
    # A DataSet/Identifier value is coerced to a string reference, not left as
    # a struct that TOML cannot encode.
    @test toml_safe(dc, Identifier(ds)) isa String
    @test toml_safe(dc, ds) isa String
    # Nested containers are recursively coerced with String keys.
    nested = toml_safe(dc, Dict(:a => [Int, QualifiedType(Bool)]))
    @test nested["a"] == ["Int64", "Bool"]
end

@testset "Collection round-trip via disk" begin
    mktempdir() do dir
        path = joinpath(dir, "Data.toml")
        stacklen = length(STACK)
        try
            dc = create!(DataCollection, "rt", path)
            @test isfile(path)
            ds = dataset!(dc, "d", Dict{String, Any}("k" => 1))
            storage!(ds, :mem, "value" => [1, 2, 3])
            loader!(ds, :idl)
            save!(dc)
            flushpendingwrites()
            @test isfile(path)
            reparsed = read(path, DataCollection)
            @test reparsed.uuid == dc.uuid
            @test reparsed.name == dc.name
            @test length(reparsed.datasets) == 1
            rds = reparsed.datasets[1]
            @test rds.name == "d"
            @test rds.parameters == Dict{String, Any}("k" => 1)
            @test DataToolkitCore.driverof(typeof(rds.storage[1])) === :mem
            @test rds.storage[1].parameters == Dict{String, Any}("value" => [1, 2, 3])
            @test DataToolkitCore.driverof(typeof(rds.loaders[1])) === :idl
        finally
            while length(STACK) > stacklen
                popfirst!(STACK)
            end
            empty!(WRITE_RECORDS)
        end
    end
end

@testset "save! debounce and flush" begin
    mktempdir() do dir
        path = joinpath(dir, "Data.toml")
        stacklen = length(STACK)
        try
            dc = create!(DataCollection, "db", path)
            # `create!` already wrote synchronously (fresh record, duration 0).
            @test isfile(path)
            @test WRITE_RECORDS[dc].write.count == 1
            @test WRITE_RECORDS[dc].queued == false
            # Inject a slow prior write with a recent invocation so the debounce
            # window is open: further save!s must coalesce, not write.
            prior = WRITE_RECORDS[dc]
            WRITE_RECORDS[dc] = WriteRecord(
                (last = time(), count = prior.invoke.count),
                (last = time(), duration = 1e6, count = prior.write.count),
                false)
            writes_before = WRITE_RECORDS[dc].write.count
            save!(dc); save!(dc); save!(dc)
            @test WRITE_RECORDS[dc].queued == true
            @test WRITE_RECORDS[dc].invoke.count > prior.invoke.count
            @test WRITE_RECORDS[dc].write.count == writes_before
            # Flushing drains the queued write and clears the record table.
            flushpendingwrites()
            @test isempty(WRITE_RECORDS)
            @test isfile(path)
        finally
            while length(STACK) > stacklen
                popfirst!(STACK)
            end
            empty!(WRITE_RECORDS)
        end
        # A locked collection is read-only; an in-memory one has no backing file.
        locked = create!(DataCollection, "lk", joinpath(dir, "Locked.toml"))
        try
            deleteat!(STACK, findfirst(c -> c === locked, STACK))
            empty!(WRITE_RECORDS)
            locked.parameters["locked"] = true
            @test !iswritable(locked)
            @test_throws ReadonlyCollection save!(locked)
        finally
            empty!(WRITE_RECORDS)
        end
        inmem = DataCollection("mem")
        @test_throws ArgumentError save!(inmem)
    end
end

@testset "refresh! on edited on-disk collection" begin
    mktempdir() do dir
        path = joinpath(dir, "Data.toml")
        uuid = string(Base.UUID(rand(UInt128)))
        writetoml(setting, extradataset) = write(path, string(
            "data_config_version = 0\n",
            "uuid = \"$uuid\"\n",
            "name = \"rf\"\n",
            "config.setting = $setting\n\n",
            "[[d1]]\nuuid = \"$(string(Base.UUID(rand(UInt128))))\"\n",
            if extradataset
                "\n[[d2]]\nuuid = \"$(string(Base.UUID(rand(UInt128))))\"\n"
            else
                ""
            end))
        writetoml(1, false)
        dc = read(path, DataCollection)
        @test config_get(dc, ["setting"]) == 1
        @test length(dc.datasets) == 1
        # An unchanged file is a no-op: mtime and dataset identity are stable.
        m0 = dc.source.mtime
        dsobj = dc.datasets[1]
        refresh!(dc)
        @test dc.source.mtime == m0
        @test dc.datasets[1] === dsobj
        # An edited config value propagates on refresh, and mtime advances.
        sleep(0.02)
        writetoml(99, false)
        touch(path)
        refresh!(dc)
        @test config_get(dc, ["setting"]) == 99
        @test dc.source.mtime != m0
        # A dataset added on disk is picked up (the list is repopulated from spec).
        sleep(0.02)
        writetoml(99, true)
        touch(path)
        refresh!(dc)
        @test length(dc.datasets) == 2
    end
end

# Ensure this runs at the end (because it defines new methods, and may affect
# state). It should simulate a basic workflow.
@testset "Dry run" begin
    # Basic storage/loader implementation for testing
    @eval begin
        import DataToolkitCore: getstorage, load, supportedtypes
        function getstorage(storage::DataStorage{:raw}, T::Type)
            get(storage, "value", nothing)::Union{T, Nothing}
        end
        supportedtypes(::Type{DataStorage{:raw}}, spec::Dict{String, Any}) =
            [QualifiedType(typeof(get(spec, "value", nothing)))]
        function load(::DataLoader{:passthrough}, from::T, ::Type{T}) where {T <: Any}
            from
        end
        supportedtypes(::Type{DataLoader{:passthrough}}, _::Dict{String, Any}, dataset::DataSet) =
            reduce(vcat, getproperty.(dataset.storage, :type)) |> unique
    end
    fieldeqn_parent_stack = []
    function fieldeqn(a::T, b::T) where {T} # field equal nested
        push!(fieldeqn_parent_stack, a)
        if T <: AbstractVector
            eq = length(a) == length(b) &&
                all(splat(fieldeqn), zip(a, b))
            pop!(fieldeqn_parent_stack)
            eq
        elseif T <: AbstractDict
            eq = length(a) == length(b)
            for k in keys(a)
                if !haskey(b, k) || !fieldeqn(a[k], b[k])
                    eq = false
                    break
                end
            end
            pop!(fieldeqn_parent_stack)
            eq
        elseif isempty(fieldnames(T))
            a == b || begin
                @info "[fieldeqn] $T differs" a b
                pop!(fieldeqn_parent_stack)
                false
            end
        else
            for field in fieldnames(T)
                if getfield(a, field) in fieldeqn_parent_stack
                elseif hasmethod(iterate, Tuple{fieldtype(T, field)}) &&
                    !all([fieldeqn(af, bf) for (af, bf) in
                              zip(getfield(a, field), getfield(b, field))])
                    @info "[fieldeqn] iterable $field of $T differs" a b
                    pop!(fieldeqn_parent_stack)
                    return false
                elseif getfield(a, field) !== a && !fieldeqn(getfield(a, field), getfield(b, field))
                    @info "[fieldeqn] $field of $T differs" a b
                    pop!(fieldeqn_parent_stack)
                    return false
                end
            end
            pop!(fieldeqn_parent_stack)
            true
        end
    end
    datatoml = """
    data_config_version = 0
    uuid = "84068d44-24db-4e28-b693-58d2e1f59d05"
    name = "datatest"

    config.setting = 123
    config.nested.value = 4

    [[dataset]]
    uuid = "d9826666-5049-4051-8d2e-fe306c20802c"
    property = 456

        [[dataset.storage]]
        driver = "raw"
        value = [1, 2, 3]

        [[dataset.loader]]
        driver = "passthrough"
    """
    datatoml_full = """
    data_config_version = 0
    uuid = "84068d44-24db-4e28-b693-58d2e1f59d05"
    name = "datatest"

    [config]
    setting = 123

        [config.nested]
        value = 4

    [[dataset]]
    uuid = "d9826666-5049-4051-8d2e-fe306c20802c"
    property = 456

        [[dataset.storage]]
        driver = "raw"
        priority = 1
        type = "Vector{Int64}"
        value = [1, 2, 3]

        [[dataset.loader]]
        driver = "passthrough"
        priority = 1
        type = "Vector{Int64}"
    """
    @test fieldeqn(read(IOBuffer(datatoml), DataCollection),
                  read(IOBuffer(datatoml_full), DataCollection))
    collection = read(IOBuffer(datatoml), DataCollection)
    @testset "Collection parsed properties" begin
        @test collection.version == 0
        @test collection.uuid == Base.UUID("84068d44-24db-4e28-b693-58d2e1f59d05")
        @test collection.name == "datatest"
        @test collection.parameters ==
            Dict{String, Any}("setting" => 123, "nested" => Dict{String, Any}("value" => 4))
        @test collection.plugins == String[]
        @test collection.source === nothing
        @test collection.mod == Main
        @test length(collection.datasets) == 1
    end
    @test_throws EmptyStackError dataset("dataset")
    @test_throws EmptyStackError getlayer()
    @test (collection = loadcollection!(IOBuffer(datatoml))) isa Any # if this actually goes wrong, it should be caught by subsequent tests
    @test getlayer() === collection
    @test_throws UnresolveableIdentifier getlayer("nope")
    @test_throws UnresolveableIdentifier getlayer(Base.UUID("11111111-24db-4e28-b693-58d2e1f59d05"))
    @testset "DataSet parsed properties" begin
        @test dataset("dataset") isa DataSet
        @test dataset("dataset").name == "dataset"
        @test dataset("dataset").uuid == Base.UUID("d9826666-5049-4051-8d2e-fe306c20802c")
        @test dataset("dataset").parameters == Dict{String, Any}("property" => 456)
    end
    @testset "Store/Load" begin
        @test length(dataset("dataset").storage) == 1
        @test dataset("dataset").storage[1].dataset === dataset("dataset")
        @test dataset("dataset").storage[1].parameters == Dict{String, Any}("value" => [1, 2, 3])
        @test dataset("dataset").storage[1].type == [QualifiedType(Vector{Int})]
        @test length(dataset("dataset").loaders) == 1
        @test dataset("dataset").loaders[1].dataset === dataset("dataset")
        @test dataset("dataset").loaders[1].parameters == Dict{String, Any}()
        @test dataset("dataset").loaders[1].type == [QualifiedType(Vector{Int})]
        @test open(dataset("dataset"), Vector{Int}) == [1, 2, 3]
        @test read(dataset("dataset"), Vector{Int}) == [1, 2, 3]
        @test read(dataset("dataset")) == [1, 2, 3]
        @test read(parse(Identifier, "dataset"), Vector{Int}) == [1, 2, 3]
        @test read(parse(Identifier, "dataset::Vector{Int}")) == [1, 2, 3]
    end
    @testset "Identifier" begin
        @test_throws UnresolveableIdentifier dataset("nonexistent")
        @test_throws UnresolveableIdentifier resolve(parse(Identifier, "nonexistent"))
        @test resolve(parse(Identifier, "dataset")) == dataset("dataset")
        @test resolve(parse(Identifier, "datatest:dataset")) == dataset("dataset")
        @test resolve(parse(Identifier, "dataset")) == dataset("dataset")
        @test resolve(parse(Identifier, "dataset::Vector{Int}")) == dataset("dataset")
        for (iargs, (col, ds)) in [((), ("datatest", "dataset")),
                                  ((:name,), ("datatest", "dataset")),
                                  ((:uuid,), (Base.UUID("84068d44-24db-4e28-b693-58d2e1f59d05"), Base.UUID("d9826666-5049-4051-8d2e-fe306c20802c"))),
                                  ((:uuid, :name), (Base.UUID("84068d44-24db-4e28-b693-58d2e1f59d05"), "dataset")),
                                  ((:name, :uuid), ("datatest", Base.UUID("d9826666-5049-4051-8d2e-fe306c20802c")))]
            ident = Identifier(dataset("dataset"), iargs...)
            @test ident == Identifier(col, ds, nothing, Dict{String, Any}("property" => 456))
            @test dataset("dataset") === resolve(ident)
            @test parse(Identifier, string(ident)) == Identifier(col, ds, nothing, Dict{String, Any}())
        end
        @test_throws ArgumentError Identifier(dataset("dataset"), :err)
        @test dataset("dataset") == dataset("dataset", "property" => 456)
        @test_throws UnresolveableIdentifier dataset("dataset", "property" => 321)
        let io = IOBuffer()
            write(io, collection)
            @test String(take!(io)) == datatoml_full
        end
    end
    @testset "Manipulation" begin
        @test stack_index(collection.uuid) == stack_index(collection.name) == stack_index(1)
        @test stack_index(2) === nothing
        @test plugin_add!(["test"]).plugins == ["test"]
        @test plugin_add!(["test2"]).plugins == ["test", "test2"]
        @test plugin_list() == ["test", "test2"]
        @test plugin_remove!(["test"]).plugins == ["test2"]
        @test plugin_remove!(["test2"]).plugins == String[]
        @test config_get(collection, ["setting"]) == 123
        @test config_get(collection, ["setting", "none"]) ===nothing
        @test config_get(collection, ["nested", "value"]) == 4
        @test config_get(collection, ["nested", "nope"]) ===nothing
        @test config_set!(["some", "nested", "val"], 5).parameters["some"] ==
            Dict{String, Any}("nested" => Dict{String, Any}("val" => 5))
        @test config_get(["some", "nested", "val"]) == 5
        @test get(config_unset!(collection, ["some"]), "some") === nothing
    end
end

@testset "Interactive creation" begin
    @eval begin
        import DataToolkitCore: createinteractive, getstorage
        # `true` means "create an empty transformer of this driver".
        createinteractive(::Type{DataStorage{:emptycreate}}, ::String) = true
        # Returns a param spec, but no display backend fills it interactively.
        createinteractive(::Type{DataStorage{:specreate}}, ::String) =
            ["url" => (; prompt="URL: ", type=String)]
        getstorage(::DataStorage{:emptycreate}, ::Type{String}) = "ok"
    end
    parent = DataToolkitCore.DataSet(DataCollection(), "ds", Dict{String, Any}("uuid" => string(Base.UUID(rand(UInt128)))))
    # `createinteractive === true` builds an empty transformer, not a MethodError.
    s = trycreateauto(parent, DataStorage{:emptycreate}, ""; interactive=true)
    @test s isa DataStorage{:emptycreate}
    # A param spec with no interactive backend yields nothing, not a MethodError
    # from `Dict{String,Any}(nothing)`.
    @test isnothing(trycreateauto(parent, DataStorage{:specreate}, ""; interactive=true))
end
