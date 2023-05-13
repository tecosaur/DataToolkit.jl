using DataToolkitBase
using Test

import DataToolkitBase: natkeygen, stringdist, stringsimilarity,
    longest_common_subsequence, highlight_lcs

@testset "Utils" begin
    @testset "Doctests" begin
        @test natkeygen.(["A1", "A10", "A02", "A1.5"]) ==
            [["a", "0\x01"], ["a", "0\n"], ["a", "0\x02"], ["a", "0\x015"]]
        @test sort(["A1", "A10", "A02", "A1.5"], by=natkeygen) ==
            ["A1", "A1.5", "A02", "A10"]
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
    end
end

@testset "Advice" begin
    # Some advice to use
    sump1 = DataAdvice(
        2, (post::Function, f::typeof(sum), i::Int) ->
            (post, f, (i+1,)))
    sumx2 = DataAdvice(
        1, (post::Function, f::typeof(sum), i::Int) ->
            (post, f, (2*i,)))
    summ3 = DataAdvice(
        1, (post::Function, f::typeof(sum), i::Int) ->
            ((x -> x-3) ∘ post, f, (i,)))
    @testset "Basic advice" begin
        # Application of advice
        @test sump1((identity, sum, (1,), (;))) ==
            (identity, sum, (2,), (;))
        # Pass-through of `post`
        @test sump1((sqrt, sum, (1,), (;))) ==
            (sqrt, sum, (2,), (;))
        # Matching the argument
        @test sump1((identity, sum, ([1],), (;))) ==
            (identity, sum, ([1],), (;))
        # Matching the kwargs
        @test sump1((identity, sum, (1,), (dims=3,))) ==
            (identity, sum, (1,), (dims = 3,))
        # Matching the function
        @test sump1((identity, sqrt, (1,), (;))) ==
            (identity, sqrt, (1,), (;))
        let # Using invokelatest on the advice function
            thing(x) = x^2
            h(x) = x+1
            thing_a = DataAdvice(
                (post::Function, f::typeof(thing), i::Int) ->
                    (post, f, (h(i),)))
            @test thing_a((identity, thing, (2,), (;))) ==
                (identity, thing, (3,), (;))
            h(x) = x+2
            @test thing_a((identity, thing, (2,), (;))) ==
                (identity, thing, (4,), (;))
        end
    end
    @testset "Amalgamation" begin
        amlg12 = DataAdviceAmalgamation(
            sump1 ∘ sumx2, [sumx2, sump1], String[], String[])
        amlg21 = DataAdviceAmalgamation(
            sumx2 ∘ sump1, [sump1, sumx2], String[], String[])
        amlg321 = DataAdviceAmalgamation(
            summ3 ∘ sumx2 ∘ sump1, [sump1, sumx2, summ3], String[], String[])
        amlg213 = DataAdviceAmalgamation(
            sumx2 ∘ sump1 ∘ summ3, [summ3, sump1, sumx2], String[], String[])
        @test amlg12((identity, sum, (2,), (;))) == (identity, sum, (5,), (;))
        @test amlg12(sum, 2) == 5
        @test amlg21(sum, 2) == 6
        @test amlg321(sum, 2) == 3
        @test amlg213(sum, 2) == 3
    end
    @testset "Plugin loading" begin
        # Empty state
        amlg = empty(DataAdviceAmalgamation)
        @test amlg.adviseall == identity
        @test amlg.advisors == DataAdvice[]
        @test amlg.plugins_wanted == String[]
        @test amlg.plugins_used == String[]
        # Create a plugin
        plg = Plugin(string(gensym()), [sump1, sumx2])
        push!(PLUGINS, plg)
        # Desire the plugin, then check the advice is incorperated correctly
        push!(amlg.plugins_wanted, plg.name)
        @test amlg.adviseall == sump1 ∘ sumx2
        @test amlg.advisors == [sumx2, sump1]
        @test amlg.plugins_wanted == [plg.name]
        @test amlg.plugins_used == [plg.name]
        # Display
        @test sprint(show, amlg) == "DataAdviceAmalgamation($(plg.name) ✔)"
    end
    @testset "Advice macro" begin
        @test :($(GlobalRef(DataToolkitBase, :_dataadvisecall))(func, x)) ==
            @macroexpand @advise func(x)
        @test :($(GlobalRef(DataToolkitBase, :_dataadvisecall))(func, x, y, z)) ==
            @macroexpand @advise func(x, y, z)
        @test :($(GlobalRef(DataToolkitBase, :_dataadvisecall))(func; a=1, b)) ==
            @macroexpand @advise func(; a=1, b)
        @test :($(GlobalRef(DataToolkitBase, :_dataadvisecall))(func, x, y, z; a=1, b)) ==
            @macroexpand @advise func(x, y, z; a=1, b)
        @test :(($(GlobalRef(DataToolkitBase, :_dataadvise))(a))(func, x)) ==
            @macroexpand @advise a func(x)
        @test :(($(GlobalRef(DataToolkitBase, :_dataadvise))(source(a)))(func, x)) ==
            @macroexpand @advise source(a) func(x)
    end
    deleteat!(PLUGINS, length(PLUGINS)) # remove `plg`
end

import DataToolkitBase: smallify

@testset "SmallDict" begin
    @testset "Construction" begin
        @test SmallDict() == SmallDict{Any, Any}([], [])
        @test SmallDict{Any, Any}() == SmallDict{Any, Any}([], [])
        @test SmallDict(:a => 1) == SmallDict{Symbol, Int}([:a], [1])
        @test SmallDict([:a => 1]) == SmallDict{Symbol, Int}([:a], [1])
        @test SmallDict{Symbol, Int}(:a => 1) == SmallDict{Symbol, Int}([:a], [1])
        @test_throws MethodError SmallDict{String, Int}(:a => 1)
        @test SmallDict(:a => 1, :b => 2) == SmallDict{Symbol, Int}([:a, :b], [1, 2])
        @test SmallDict(:a => 1, :b => '1') == SmallDict{Symbol, Any}([:a, :b], [1, '1'])
        @test SmallDict(:a => 1, "b" => '1') == SmallDict{Any, Any}([:a, "b"], [1, '1'])
    end
    @testset "Conversion" begin
        @test convert(SmallDict, Dict(:a => 1)) == SmallDict{Symbol, Int}([:a], [1])
        @test convert(SmallDict, Dict{Symbol, Any}(:a => 1)) == SmallDict{Symbol, Any}([:a], [1])
        @test convert(SmallDict, Dict(:a => 1, :b => '1')) == SmallDict{Symbol, Any}([:a, :b], [1, '1'])
        @test smallify(Dict(:a => Dict(:b => Dict(:c => 3)))) ==
            SmallDict(:a => SmallDict(:b => SmallDict(:c => 3)))
    end
    @testset "AbstractDict interface" begin
        d = SmallDict{Symbol, Int}()
        @test length(d) == 0
        @test haskey(d, :a) == false
        @test get(d, :a, nothing) === nothing
        @test iterate(d) === nothing
        @test (d[:a] = 1) == 1
        @test d[:a] == 1
        @test collect(d) == [:a => 1]
        @test length(d) == 1
        @test haskey(d, :a) == true
        @test get(d, :a, nothing) == 1
        @test iterate(d) == (:a => 1, 2)
        @test iterate(d, 2) === nothing
        @test (d[:b] = 2) == 2
        @test length(d) == 2
        @test keys(d) == [:a, :b]
        @test values(d) == [1, 2]
        @test iterate(d, 2) === (:b => 2, 3)
        @test Dict(d) == Dict(:a => 1, :b => 2)
        @test (d[:a] = 3) == 3
        @test d[:a] == 3
        @test values(d) == [3, 2]
        @test_throws KeyError d[:c]
        delete!(d, :a)
        @test keys(d) == [:b]
        delete!(d, :b)
        @test d == empty(d)
    end
end

@testset "QualifiedType" begin
    @testset "Construction" begin
        @test QualifiedType(:a, :b) == QualifiedType(:a, :b, ())
        @test QualifiedType(Any) == QualifiedType(:Core, :Any, ())
        @test QualifiedType(Int) == QualifiedType(:Core, nameof(Int), ())
        @test QualifiedType(IO) == QualifiedType(:Core, :IO, ())
        # This test currently fails due to typevar inequivalence
        # @test QualifiedType(QualifiedType) ==
        #     QualifiedType(:DataToolkitBase, :QualifiedType, (TypeVar(:T, Union{}, Tuple),))
        @test QualifiedType(QualifiedType(:a, :b)) == QualifiedType(:a, :b, ())
    end
    @testset "Typeification" begin
        @test typeify(QualifiedType(:a, :b)) === nothing
        @test typeify(QualifiedType(:Core, :Int)) == Int
        @test typeify(QualifiedType(:Core, :IO)) == IO
        @test typeify(QualifiedType(:DataToolkitBase, :QualifiedType,
                                    (TypeVar(:T, Union{}, Tuple),))) ==
                                        QualifiedType
        @test typeify(QualifiedType(:Core, :Array, (QualifiedType(:Core, :Integer, ()), 1))) ==
            Vector{Integer}
        # Test module expansion with unexported type
        @test typeify(QualifiedType(:Main, :AnyDict, ())) === nothing
        @test typeify(QualifiedType(:Main, :AnyDict, ()), mod=Base) == Base.AnyDict
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

import DataToolkitBase: get_package, addpkg

@testset "UsePkg" begin
    @testset "add/get package" begin
        test = Base.PkgId(Base.UUID("8dfed614-e22c-5e08-85e1-65c5234f0b40"), "Test")
        @test get_package(test) === Test
        @test_throws UnregisteredPackage get_package(@__MODULE__, :Test)
        @test addpkg(@__MODULE__, :Test, "8dfed614-e22c-5e08-85e1-65c5234f0b40") isa Any
        @test @addpkg(Test, "8dfed614-e22c-5e08-85e1-65c5234f0b40") isa Any
        @test get_package(@__MODULE__, :Test) === Test
    end
    @testset "@import" begin
        nolinenum(blk) = Expr(:block, filter(e -> !(e isa LineNumberNode), blk.args)...)
        getpkg = GlobalRef(DataToolkitBase, :get_package)
        mod = GlobalRef(Core, :Module)
        gensymidx() = parse(Int, last(split(String(gensym()), '#')))
        function nextgensym(tag::String, next::Int=1)
            Symbol("##$tag#$(gensymidx()+next)")
        end
        @test quote
            A = $getpkg($Main, :A)
            A isa $mod || return A
        end |> nolinenum == @macroexpand @import A
        @test quote
            A = $getpkg($Main, :A)
            A isa $mod || return A
            B = $getpkg($Main, :B)
            B isa $mod || return B
            C = $getpkg($Main, :C)
            C isa $mod || return C
        end |> nolinenum == @macroexpand @import A, B, C
        @test quote
            B = $getpkg($Main, :A)
            B isa $mod || return B
        end |> nolinenum == @macroexpand @import A as B
        @test quote
            A = $getpkg($Main, :A)
            A isa $mod || return A
            C = $getpkg($Main, :B)
            C isa $mod || return C
            D = $getpkg($Main, :D)
            D isa $mod || return D
        end |> nolinenum == @macroexpand @import A, B as C, D
        sA = nextgensym("A")
        @test quote
            $sA = $getpkg($Main, :A)
            $sA isa $mod || return $sA
            B = ($sA).B
        end |> nolinenum == @macroexpand @import A.B
        @test quote
            A = $getpkg($Main, :A)
            A isa $mod || return A
            B = A.B
        end |> nolinenum == @macroexpand @import A, A.B
        @test quote
            A = $getpkg($Main, :A)
            A isa $mod || return A
            C = A.B
        end |> nolinenum == @macroexpand @import A, A.B as C
        @test quote
            B = $getpkg($Main, :A)
            B isa $mod || return B
            C = B.B.C
        end |> nolinenum == @macroexpand @import A as B, A.B.C
        sA = nextgensym("A")
        @test quote
            $sA = $getpkg($Main, :A)
            $sA isa $mod || return $sA
            B = ($sA).B
        end |> nolinenum == @macroexpand @import A: B
        sA = nextgensym("A")
        @test quote
            $sA = $getpkg($Main, :A)
            $sA isa $mod || return $sA
            C = ($sA).B.C
        end |> nolinenum == @macroexpand @import A: B.C
        sA = nextgensym("A", 3)
        sB = nextgensym("B")
        @test quote
            $sA = $getpkg($Main, :A)
            $sA isa $mod || return $sA
            $sB = ($sA).B
            C = ($sB).C
        end |> nolinenum == @macroexpand @import A.B: C
        sA = nextgensym("A")
        @test quote
            $sA = $getpkg($Main, :A)
            $sA isa $mod || return $sA
            C = ($sA).B
        end |> nolinenum == @macroexpand @import A: B as C
        sA = nextgensym("A")
        @test quote
            $sA = $getpkg($Main, :A)
            $sA isa $mod || return $sA
            C = ($sA).B
            E = ($sA).D
        end |> nolinenum == @macroexpand @import A: B as C, D as E
        sA = nextgensym("A")
        @test quote
            $sA = $getpkg($Main, :A)
            $sA isa $mod || return $sA
            B = ($sA).B
            C = ($sA).C
            D = ($sA).D
        end |> nolinenum == @macroexpand @import A: B, C, D
        sA = nextgensym("A")
        @test quote
            $sA = $getpkg($Main, :A)
            $sA isa $mod || return $sA
            C = ($sA).B
            D = ($sA).D
            F = ($sA).E
            G = ($sA).G
        end |> nolinenum == @macroexpand @import A: B as C, D, E as F, G
    end
end

@testset "stringification" begin
    @testset "QualifiedType" begin
        for (str, qt) in [("a.b", QualifiedType(:a, :b)),
                          ("String", QualifiedType(String)),
                          ("Array{Bool,2}", QualifiedType(Array{Bool, 2})),
                          ("Array{Array{Array{<:Integer,1},1},1}",
                           QualifiedType(Array{Array{Array{<:Integer,1},1},1})),
                          ("Ref{I<:Integer}", QualifiedType(Ref{I} where {I <: Integer}))]
            @test str == string(qt)
            # Due to TypeVar comparison issues, instead of
            # the following test, we'll do a round-trip instead.
            # @test parse(QualifiedType, str) == qt
            @test str == string(parse(QualifiedType, str))
        end
    end
    @testset "Identifiers" begin
        for (istr, ident) in [("a", Identifier(nothing, "a", nothing, SmallDict{String, Any}())),
                              ("a:b", Identifier("a", "b", nothing, SmallDict{String, Any}())),
                              ("a::Main.sometype", Identifier(nothing, "a", QualifiedType(:Main, :sometype), SmallDict{String, Any}())),
                              ("a:b::Bool", Identifier("a", "b", QualifiedType(:Core, :Bool), SmallDict{String, Any}()))]
            @test parse(Identifier, istr; advised=true) == ident
            @test istr == string(ident)
        end
    end
end

# Ensure this runs at the end, it should simulate a basic workflow
@testset "Dry run" begin
    # Basic storage/loader implementation for testing
    @eval begin
        import DataToolkitBase: getstorage, load, supportedtypes
        function getstorage(storage::DataStorage{:raw}, T::Type)
            get(storage, "value", nothing)::Union{T, Nothing}
        end
        supportedtypes(::Type{DataStorage{:raw}}, spec::SmallDict{String, Any}) =
            [QualifiedType(typeof(get(spec, "value", nothing)))]
        function load(::DataLoader{:passthrough}, from::T, ::Type{T}) where {T <: Any}
            from
        end
        supportedtypes(::Type{DataLoader{:passthrough}}, _::SmallDict{String, Any}, dataset::DataSet) =
            reduce(vcat, getproperty.(dataset.storage, :type)) |> unique
    end
    datatoml = """
    data_config_version = 0
    uuid = "84068d44-24db-4e28-b693-58d2e1f59d05"
    name = "datatest"

    config.setting = 123

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

    [[dataset]]
    uuid = "d9826666-5049-4051-8d2e-fe306c20802c"
    property = 456

        [[dataset.storage]]
        driver = "raw"
        priority = 1
        type = "Array{Int64,1}"
        value = [1, 2, 3]

        [[dataset.loader]]
        driver = "passthrough"
        priority = 1
        type = "Array{Int64,1}"
    """
    collection = read(IOBuffer(datatoml), DataCollection)
    @test collection.version == 0
    @test collection.uuid == Base.UUID("84068d44-24db-4e28-b693-58d2e1f59d05")
    @test collection.name == "datatest"
    @test collection.parameters == SmallDict{String, Any}("setting" => 123)
    @test collection.plugins == String[]
    @test collection.path === nothing
    @test collection.mod == Main
    @test length(collection.datasets) == 1
    @test_throws EmptyStackError dataset("dataset")
    push!(STACK, collection)
    @test_throws UnresolveableIdentifier dataset("nonexistent")
    @test dataset("dataset") isa DataSet
    @test dataset("dataset").name == "dataset"
    @test dataset("dataset").uuid == Base.UUID("d9826666-5049-4051-8d2e-fe306c20802c")
    @test dataset("dataset").parameters == SmallDict{String, Any}("property" => 456)
    @test length(dataset("dataset").storage) == 1
    @test dataset("dataset").storage[1].dataset === dataset("dataset")
    @test dataset("dataset").storage[1].parameters == SmallDict{String, Any}("value" => [1, 2, 3])
    @test dataset("dataset").storage[1].type == [QualifiedType(Vector{Int})]
    @test length(dataset("dataset").loaders) == 1
    @test dataset("dataset").loaders[1].dataset === dataset("dataset")
    @test dataset("dataset").loaders[1].parameters == SmallDict{String, Any}()
    @test dataset("dataset").loaders[1].type == [QualifiedType(Vector{Int})]
    @test open(dataset("dataset"), Vector{Int}) == [1, 2, 3]
    @test read(dataset("dataset"), Vector{Int}) == [1, 2, 3]
    @test read(dataset("dataset")) == [1, 2, 3]
    @test dataset("dataset") == dataset("dataset", "property" => 456)
    @test_throws UnresolveableIdentifier dataset("dataset", "property" => 321)
    let io = IOBuffer()
        write(io, collection)
        @test String(take!(io)) == datatoml_full
    end
end
