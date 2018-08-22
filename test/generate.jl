temp_pkg_dir() do tmp; cd(tmp) do
    @testset "generating a package with .jl extension" begin
        pkg = "PackageWithExtension"
        PkgDev.generate(pkg*".jl", "MIT", config=Dict("user.name"=>"Julia Test", "user.email"=>"test@julialang.org"))
        testfile = joinpath(pkg, "test", "runtests.jl")
        s = replace(read(testfile, String), "@test 1 == 2" => "@test 1 == 1")
        write(testfile, s)
        Pkg.develop(PackageSpec(path="PackageWithExtension"))
        @test "PackageWithExtension" in keys(Pkg.installed())
        Pkg.test("PackageWithExtension")
    end
end end
