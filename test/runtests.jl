using PkgDev
using Test, Pkg, Random, LibGit2

function temp_pkg_dir(fn::Function)
    local env_dir
    local old_load_path
    local old_depot_path
    local old_home_project
    local old_active_project
    try
        old_load_path = copy(LOAD_PATH)
        old_depot_path = copy(DEPOT_PATH)
        old_home_project = Base.HOME_PROJECT[]
        old_active_project = Base.ACTIVE_PROJECT[]
        empty!(LOAD_PATH)
        empty!(DEPOT_PATH)
        Base.HOME_PROJECT[] = nothing
        Base.ACTIVE_PROJECT[] = nothing
        mktempdir() do env_dir
            mktempdir() do depot_dir
                push!(LOAD_PATH, "@", "@v#.#", "@stdlib")
                push!(DEPOT_PATH, depot_dir)
                fn(env_dir)
            end
        end
    finally
        empty!(LOAD_PATH)
        empty!(DEPOT_PATH)
        append!(LOAD_PATH, old_load_path)
        append!(DEPOT_PATH, old_depot_path)
        Base.HOME_PROJECT[] = old_home_project
        Base.ACTIVE_PROJECT[] = old_active_project
    end
end

temp_pkg_dir() do pkgdir; cd(pkgdir) do
    @testset "testing a package with test dependencies causes them to be installed for the duration of the test" begin
        PkgDev.generate("PackageWithTestDependencies", "MIT", config=Dict("user.name"=>"Julia Test", "user.email"=>"test@julialang.org"))
        Pkg.dev("PackageWithTestDependencies")

        isdir(Pkg.dir("PackageWithTestDependencies","test")) || mkdir(Pkg.dir("PackageWithTestDependencies","test"))
        open(Pkg.dir("PackageWithTestDependencies","test","REQUIRE"),"w") do f
            println(f,"Example")
        end

        open(Pkg.dir("PackageWithTestDependencies","test","runtests.jl"),"w") do f
            println(f, "using " * (false ? "Base." : "") * "Test")
            if VERSION >= v"0.7.0-DEV.3656"
                println(f, "using Pkg")
            end
            println(f, "@test haskey(Pkg.installed(), \"Example\")")
        end

        Pkg.resolve()
        @test [keys(Pkg.installed())...] == ["PackageWithTestDependencies"]

        Pkg.test("PackageWithTestDependencies")

        @test [keys(Pkg.installed())...] == ["PackageWithTestDependencies"]

        # trying to pin an unregistered package errors
        try
            Pkg.pin("PackageWithTestDependencies", v"1.0.0")
            error("unexpected")
        catch err
            @test isa(err, PkgDevError)
            @test err.msg == "PackageWithTestDependencies cannot be pinned – not a registered package"
        end
    end

    @testset "generating a package with .jl extension" begin
        PkgDev.generate("PackageWithExtension.jl", "MIT", config=Dict("user.name"=>"Julia Test", "user.email"=>"test@julialang.org"))
        @show keys(Pkg.installed())
        @test "PackageWithExtension" in keys(Pkg.installed())
    end

    @testset "testing a package with no runtests.jl errors" begin
        PkgDev.generate("PackageWithNoTests", "MIT", config=Dict("user.name"=>"Julia Test", "user.email"=>"test@julialang.org"))

        if isfile(Pkg.dir("PackageWithNoTests", "test", "runtests.jl"))
            Base.rm(Pkg.dir("PackageWithNoTests", "test", "runtests.jl"))
        end

        try
            Pkg.test("PackageWithNoTests")
            error("unexpected")
        catch err
            @test err.msg == "PackageWithNoTests did not provide a test/runtests.jl file"
        end
    end

    @testset "testing a package with failing tests errors" begin
        PkgDev.generate("PackageWithFailingTests", "MIT", config=Dict("user.name"=>"Julia Test", "user.email"=>"test@julialang.org"))

        isdir(Pkg.dir("PackageWithFailingTests","test")) || mkdir(Pkg.dir("PackageWithFailingTests","test"))
        open(Pkg.dir("PackageWithFailingTests", "test", "runtests.jl"),"w") do f
            println(f, "using " * (false ? "Base." : "") * "Test")
            println(f, "@test false")
        end

        try
            Pkg.test("PackageWithFailingTests")
            error("unexpected")
        catch err
            @test err.msg == "PackageWithFailingTests had test errors"
        end
    end

    # FIXME coverage is currently broken on windows?
    Sys.isunix() && @testset "testing with code-coverage" begin
        PkgDev.generate("PackageWithCodeCoverage", "MIT", config=Dict("user.name"=>"Julia Test", "user.email"=>"test@julialang.org"))

        src = """
module PackageWithCodeCoverage

export f1, f2, f3, untested

f1(x) = 2x
f2(x) = f1(x)
function f3(x)
    3x
end
untested(x) = 7

end"""
        linetested = [false, false, false, false, true, true, false, true, false, false]
        open(Pkg.dir("PackageWithCodeCoverage", "src", "PackageWithCodeCoverage.jl"), "w") do f
            println(f, src)
        end
        isdir(Pkg.dir("PackageWithCodeCoverage","test")) || mkdir(Pkg.dir("PackageWithCodeCoverage","test"))
        open(Pkg.dir("PackageWithCodeCoverage", "test", "runtests.jl"),"w") do f
            println(f, "using PackageWithCodeCoverage")
            println(f, "using " * (false ? "Base." : "") * "Test")
            println(f, "@test f2(2) == 4")
            println(f, "@test f3(5) == 15")
        end

        let codecov_yml = Pkg.dir("PackageWithCodeCoverage", ".codecov.yml")
            @test isfile(codecov_yml)
            @test readchomp(codecov_yml) == "comment: false"
        end

        Pkg.test("PackageWithCodeCoverage")
        covdir = Pkg.dir("PackageWithCodeCoverage","src")
        covfiles = filter!(x -> occursin("PackageWithCodeCoverage.jl", x) && occursin(".cov", x), readdir(covdir))
        @test isempty(covfiles)
        Pkg.test("PackageWithCodeCoverage", coverage=true)
        covfiles = filter!(x -> occursin("PackageWithCodeCoverage.jl", x) && occursin(".cov", x), readdir(covdir))
        @test !isempty(covfiles)
        for file in covfiles
            @test isfile(joinpath(covdir,file))
            covstr = read(joinpath(covdir,file), String)
            srclines = split(src, '\n')
            covlines = split(covstr, '\n')
            for i = 1:length(linetested)
                covline = (linetested[i] ? "        1 " : "        - ")*srclines[i]
                @test covlines[i] == covline
            end
        end
    end

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

    @testset "testing freeable" begin
        Pkg.add("Example")
        io = IOBuffer()
        f = PkgDev.freeable(io)
        @test !(any(f .== "Example") || occursin("Example", String(take!(io))))
        Pkg.checkout("Example")
        f = PkgDev.freeable(io)
        @test any(f .== "Example") || occursin("Example", String(take!(io)))
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
