using DataToolkitCore
using Test

import DataToolkitCore: natkeygen, stringdist, stringsimilarity,
    longest_common_subsequence, highlight_lcs, referenced_datasets,
    stack_index, plugin_add, plugin_list, plugin_remove, config_get,
    config_set, config_unset, reinit, DATASET_REFERENCE_WRAPPER

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
        # Invalid advice function
        @test_throws ArgumentError Advice(() -> ())
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
        @test reinit(AdviceAmalgamation(amlg)).advisors == amlg.advisors
        let cltn = DataCollection()
            push!(cltn.plugins, plg.name)
            @test reinit(AdviceAmalgamation(cltn)).advisors == amlg.advisors
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
        @test :(($(GlobalRef(DataToolkitCore, :_dataadvise))(a))(func, x)) ==
            @macroexpand @advise a func(x)
        @test :(($(GlobalRef(DataToolkitCore, :_dataadvise))(source(a)))(func, x)) ==
            @macroexpand @advise source(a) func(x)
        @test_throws LoadError eval(:(@advise (1, 2)))
        @test_throws LoadError eval(:(@advise f()))
        @test 2 == @advise sump1 sum(1)
        @test 2 == @advise [sump1] sum(1)
        @test 2 == @advise AdviceAmalgamation([sump1]) sum(1)
    end
    deleteat!(PLUGINS, length(PLUGINS)) # remove `plg`
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
        @test typeify(QualifiedType(:a, :b)) === nothing
        @test typeify(QualifiedType(:Core, :Int)) == Int
        @test typeify(QualifiedType(:Core, :IO)) == IO
        @test typeify(QualifiedType(:DataToolkitCore, :QualifiedType, ())) == QualifiedType
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

import DataToolkitCore: get_package, addpkg

@testset "UsePkg" begin
    @testset "add/get package" begin
        test = Base.PkgId(Base.UUID("8dfed614-e22c-5e08-85e1-65c5234f0b40"), "Test")
        @test get_package(test) === Test
        @test_throws UnregisteredPackage get_package(@__MODULE__, :Test)
        @test addpkg(@__MODULE__, :Test, "8dfed614-e22c-5e08-85e1-65c5234f0b40") isa Any
        @test @addpkg(Test, "8dfed614-e22c-5e08-85e1-65c5234f0b40") isa Any
        @test get_package(@__MODULE__, :Test) === Test
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
        for (istr, ident) in [("a", Identifier(nothing, "a", nothing, Dict{String, Any}())),
                              ("a:b", Identifier("a", "b", nothing, Dict{String, Any}())),
                              ("a::Main.sometype", Identifier(nothing, "a", QualifiedType(:Main, :sometype), Dict{String, Any}())),
                              ("a:b::Bool", Identifier("a", "b", QualifiedType(:Core, :Bool), Dict{String, Any}()))]
            @test parse_ident(istr) == ident
            @test istr == string(ident)
        end
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
        type = "Array{Int64,1}"
        value = [1, 2, 3]

        [[dataset.loader]]
        driver = "passthrough"
        priority = 1
        type = "Array{Int64,1}"
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
        @test collection.path === nothing
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
        @test resolve(parse(Identifier, "dataset::Vector{Int}")) == read(dataset("dataset"))
        @test resolve(parse(Identifier, "dataset::Vector{Int}"), resolvetype=false) == dataset("dataset")
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
        @test plugin_add(["test"]).plugins == ["test"]
        @test plugin_add(["test2"]).plugins == ["test", "test2"]
        @test plugin_list() == ["test", "test2"]
        @test plugin_remove(["test"]).plugins == ["test2"]
        @test plugin_remove(["test2"]).plugins == String[]
        @test config_get(collection, ["setting"]) == 123
        @test config_get(collection, ["setting", "none"]) ===nothing
        @test config_get(collection, ["nested", "value"]) == 4
        @test config_get(collection, ["nested", "nope"]) ===nothing
        @test config_set(["some", "nested", "val"], 5).parameters["some"] ==
            Dict{String, Any}("nested" => Dict{String, Any}("val" => 5))
        @test config_get(["some", "nested", "val"]) == 5
        @test get(config_unset(collection, ["some"]), "some") === nothing
    end
end
