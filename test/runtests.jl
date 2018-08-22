using PkgDev
using Test, Pkg, Random, LibGit2

# include("generate.jl")
include("registry.jl")

#=
    if haskey(ENV, "CI") && lowercase(ENV["CI"]) == "true"
        @info("setting git global configuration")
        run(`git config --global user.name "Julia Test"`)
        run(`git config --global user.email test@julialang.org`)
        run(`git config --global github.user JuliaTest`)
    end

    @testset "testing package tags" begin
        PkgDev.generate("PackageWithTags", "MIT", config=Dict("user.name"=>"Julia Test", "user.email"=>"test@julialang.org"))
        PkgDev.register("PackageWithTags")
        PkgDev.tag("PackageWithTags")
        PkgDev.tag("PackageWithTags")

        # check tags
        repo = LibGit2.GitRepo(joinpath(pkgdir, "PackageWithTags"))
        meta_repo = LibGit2.GitRepo(joinpath(pkgdir, "METADATA"))
        try
            tags = LibGit2.tag_list(repo)
            @test ("v0.0.1" in tags)
            @test ("v0.0.2" in tags)
            # test that those version files exist
            @test ispath(joinpath(pkgdir, "METADATA", "PackageWithTags",
                                  "versions", "0.0.1", "sha1"))
            # check that we actually commited those files to METADATA
            # (this test always succeeds for some reason -- we should be using
            #  git_diff_index_to_workdir here)
            @test LibGit2.isdirty(meta_repo) == false
        finally
            finalize(repo)
            finalize(meta_repo)
        end
    end


    @testset "testing package registration" begin
        PkgDev.generate("GreatNewPackage", "MIT", config=Dict("user.name"=>"Julia Test", "user.email"=>"test@julialang.org"))
        PkgDev.register("GreatNewPackage")
        @test !isempty(read(joinpath(pkgdir, "METADATA", "GreatNewPackage", "url"), String))
    end
end end

@testset "Testing package utils" begin
    @test PkgDev.getrepohttpurl("https://github.com/JuliaLang/PkgDev.jl.git") == "https://github.com/JuliaLang/PkgDev.jl"
    @test PkgDev.getrepohttpurl("git://github.com/JuliaLang/PkgDev.jl.git")  == "https://github.com/JuliaLang/PkgDev.jl"
end
=#
