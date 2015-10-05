using PkgDev
using Base.Test
import Base.Pkg.PkgError

function temp_pkg_dir(fn::Function, remove_tmp_dir::Bool=true)
    # Used in tests below to setup and teardown a sandboxed package directory
    const tmpdir = ENV["JULIA_PKGDIR"] = joinpath(tempdir(),randstring())
    @test !isdir(Pkg.dir())
    try
        Pkg.init()
        @test isdir(Pkg.dir())
        Pkg.resolve()

        fn()
    finally
        remove_tmp_dir && rm(tmpdir, recursive=true)
    end
end

# testing a package with test dependencies causes them to be installed for the duration of the test
temp_pkg_dir() do
    Pkg.generate("PackageWithTestDependencies", "MIT", config=Dict("user.name"=>"Julia Test", "user.email"=>"test@julialang.org"))
    @test [keys(Pkg.installed())...] == ["PackageWithTestDependencies"]
    @test readall(Pkg.dir("PackageWithTestDependencies","REQUIRE")) == "julia $(Pkg.Generate.versionfloor(VERSION))\n"

    isdir(Pkg.dir("PackageWithTestDependencies","test")) || mkdir(Pkg.dir("PackageWithTestDependencies","test"))
    open(Pkg.dir("PackageWithTestDependencies","test","REQUIRE"),"w") do f
        println(f,"Example")
    end

    open(Pkg.dir("PackageWithTestDependencies","test","runtests.jl"),"w") do f
        println(f,"using Base.Test")
        println(f,"@test haskey(Pkg.installed(), \"Example\")")
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
        @test isa(err, PkgError)
        @test err.msg == "PackageWithTestDependencies cannot be pinned – not a registered package"
    end
end

# testing a package with no runtests.jl errors
temp_pkg_dir() do
    Pkg.generate("PackageWithNoTests", "MIT", config=Dict("user.name"=>"Julia Test", "user.email"=>"test@julialang.org"))

    if isfile(Pkg.dir("PackageWithNoTests", "test", "runtests.jl"))
        rm(Pkg.dir("PackageWithNoTests", "test", "runtests.jl"))
    end

    try
        Pkg.test("PackageWithNoTests")
        error("unexpected")
    catch err
        @test err.msg == "PackageWithNoTests did not provide a test/runtests.jl file"
    end
end

# testing a package with failing tests errors
temp_pkg_dir() do
    Pkg.generate("PackageWithFailingTests", "MIT", config=Dict("user.name"=>"Julia Test", "user.email"=>"test@julialang.org"))

    isdir(Pkg.dir("PackageWithFailingTests","test")) || mkdir(Pkg.dir("PackageWithFailingTests","test"))
    open(Pkg.dir("PackageWithFailingTests", "test", "runtests.jl"),"w") do f
        println(f,"using Base.Test")
        println(f,"@test false")
    end

    try
        Pkg.test("PackageWithFailingTests")
        error("unexpected")
    catch err
        @test err.msg == "PackageWithFailingTests had test errors"
    end
end

# Testing with code-coverage
temp_pkg_dir() do
    Pkg.generate("PackageWithCodeCoverage", "MIT", config=Dict("user.name"=>"Julia Test", "user.email"=>"test@julialang.org"))

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
        println(f,"using PackageWithCodeCoverage, Base.Test")
        println(f,"@test f2(2) == 4")
        println(f,"@test f3(5) == 15")
    end

    Pkg.test("PackageWithCodeCoverage")
    covdir = Pkg.dir("PackageWithCodeCoverage","src")
    covfiles = filter!(x -> contains(x, "PackageWithCodeCoverage.jl") && contains(x,".cov"), readdir(covdir))
    @test isempty(covfiles)
    Pkg.test("PackageWithCodeCoverage", coverage=true)
    covfiles = filter!(x -> contains(x, "PackageWithCodeCoverage.jl") && contains(x,".cov"), readdir(covdir))
    @test !isempty(covfiles)
    for file in covfiles
        @test isfile(joinpath(covdir,file))
        covstr = readall(joinpath(covdir,file))
        srclines = split(src, '\n')
        covlines = split(covstr, '\n')
        for i = 1:length(linetested)
            covline = (linetested[i] ? "        1 " : "        - ")*srclines[i]
            @test covlines[i] == covline
        end
    end
end

# issue #13373
temp_pkg_dir() do
    Pkg.generate("Foo", "MIT", config=Dict("user.name"=>"Julia Test", "user.email"=>"test@julialang.org"))
    PkgDev.tag("Foo")
    PkgDev.tag("Foo")
end