using DataToolkitBase
using DataToolkitCore
using Test

@testset "Re-export surface" begin
    macros = [Symbol("@d_str"), Symbol("@load"),
              Symbol("@require"), Symbol("@addpkg")]
    @testset "exported macros are bound" begin
        for m in macros
            @test isdefined(DataToolkitBase, m)
        end
        @test Set(names(DataToolkitBase)) ⊇ Set(macros)
    end
    @testset "hand-written aliases pin Core macros" begin
        @test DataToolkitBase.var"@require" === DataToolkitCore.var"@require"
        @test DataToolkitBase.var"@addpkg" === DataToolkitCore.var"@addpkg"
        @test (@macroexpand1 @addpkg Foo "00000000-0000-0000-0000-000000000000") isa Expr
    end
    @testset "macro dependencies reachable through the shim" begin
        for sym in (:dataset, :Identifier, :loadcollection!)
            @test isdefined(DataToolkitBase, sym)
        end
    end
end

@testset "@addpkg / @require round-trip" begin
    testuuid = "8dfed614-e22c-5e08-85e1-65c5234f0b40"
    M = Module(:AddpkgScratch)
    Core.eval(M, :(using DataToolkitBase))
    Core.eval(M, :(@addpkg Test $testuuid))
    @test haskey(DataToolkitCore.EXTRA_PACKAGES, M)
    @test DataToolkitCore.EXTRA_PACKAGES[M][:Test] ==
        Base.PkgId(Base.UUID(testuuid), "Test")
    Core.eval(M, :(getpkg() = (@require Test; Test)))
    @test Core.eval(M, :(getpkg())) === Test
end

@testset "@d_str expansion" begin
    ex = @macroexpand1 @d_str "x"
    @test ex isa Expr
    refs = Set{Symbol}()
    walk(e::Expr) = foreach(walk, e.args)
    walk(q::QuoteNode) = walk(q.value)
    walk(g::GlobalRef) = push!(refs, g.name)
    walk(s::Symbol) = push!(refs, s)
    walk(_) = nothing
    walk(ex)
    @test :dataset in refs
    @test :read in refs
    @test :Identifier in refs
end
