using DataToolkitBase
using DataToolkitCommon
using DataFrames
using Test

DataToolkitBase.loadcollection!("Data.toml")

@testset "Storage" begin
end

@testset "Loaders/Writers" begin
    @testset "arrow" begin
        @test size(read(dataset("iris-arrow"))) == (150, 5)
    end
    @testset "compression" begin
        iris = read(dataset("iris"), Matrix)
        @test read(dataset("iris-bzip2"), Matrix) == iris
        @test read(dataset("iris-gz"), Matrix) == iris
        @test read(dataset("iris-xz"), Matrix) == iris
        @test read(dataset("iris-zstd"), Matrix) == iris
    end
    @testset "csv" begin
        @test size(read(dataset("iris"), DataFrame)) == (150, 5)
    end
    @testset "gpkg" begin
        geo = read(dataset("eurostat-gpkg"))
        using ArchGDAL
        @test geo isa ArchGDAL.IDataset
        @test ArchGDAL.getlayer(geo, 0) |> length == 1025
    end
    @testset "jpeg" begin
        @test read(dataset("lighthouse-jpeg"), Matrix) isa Matrix
    end
    @testset "jld2" begin
        @test size(read(dataset("iris-jld2"))) == (150, 5)
    end
    @testset "netpbm" begin
        # Currently broken, see <https://github.com/JuliaIO/Netpbm.jl/issues/39>
        # @test read(dataset("lighthouse-netpbm"), Matrix) isa Matrix
    end
    @testset "png" begin
        @test read(dataset("lighthouse-png"), Matrix) isa Matrix
    end
    @testset "qoi" begin
        @test read(dataset("lighthouse-qoi"), Matrix) isa Matrix
    end
    @testset "tar" begin
        @test sum(Vector{UInt8}(read(dataset("iris-tar"), String))) == 258587
    end
    @testset "tiff" begin
        @test read(dataset("lighthouse-tiff"), AbstractMatrix) isa AbstractMatrix
    end
    @testset "toml" begin
        @test sort([k => length(v) for (k, v) in read(dataset("sample-toml"))], by=first) ==
            ["database" => 4, "owner" => 2, "servers" => 2, "title" => 12]
    end
    @testset "yaml" begin
        @test sort([k => length(v) for (k, v) in read(dataset("sample-yaml"))], by=first) ==
            ["database" => 4, "owner" => 2, "servers" => 2, "title" => 12]
    end
    @testset "zip" begin
        @test sum(read(read(dataset("iris-zip"), IO))) == 258587
    end
end

@testset "Plugins" begin
    @testset "Cache" begin
    end
    @testset "Defaults" begin
    end
    @testset "Log" begin
    end
    @testset "Memorise" begin
    end
    @testset "Store" begin
        @testset "Checksums" begin
            val = "Aren't checksums neat?\n"
            @test read(dataset("checksum-k12"),    String) == val
            @test read(dataset("checksum-crc32c"), String) == val
            @test read(dataset("checksum-md5"),    String) == val
            @test read(dataset("checksum-sha1"),   String) == val
            @test read(dataset("checksum-sha224"), String) == val
            @test read(dataset("checksum-sha256"), String) == val
            @test read(dataset("checksum-sha384"), String) == val
            @test read(dataset("checksum-sha512"), String) == val
        end
    end
    @testset "Versions" begin
    end
end
