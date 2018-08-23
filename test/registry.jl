module RegistryTest

using Test
using Pkg
using Pkg.Types
using PkgDev
import LibGit2

include("utils.jl")

replace_in_file(f, pat) = write(f, replace(read(f, String), pat))

temp_pkg_dir() do project_path; cd(project_path) do
    # Create a registry
    registry_path = joinpath(DEPOT_PATH[1], "registries", "CustomReg");
    PkgDev.Registry.create_registry(registry_path, repo = registry_path, description = "This is a reg")
    pkgs = mktempdir()
    pkgdir = joinpath(pkgs, "TheFirst")
    PkgDev.generate(pkgdir, "MIT")
    # for testing
    cd(pkgdir) do
        run(`git remote remove origin`)
        run(`git remote add origin $pkgdir`)
    end
    PkgDev.Registry.register(registry_path, joinpath(pkgs, "TheFirst"))
    # Version already installed
    @test_throws PkgError PkgDev.Registry.register(registry_path, joinpath(pkgs, "TheFirst"))
    Pkg.add("TheFirst")
    @test Pkg.installed()["TheFirst"] == v"0.1.0"
     # Add an stdlib dep and update it to v0.2.0
    Pkg.activate(pkgdir)
    Pkg.add("Random")
    replace_in_file(joinpath(pkgdir, "Project.toml"), "version = \"0.1.0\"" => "version = \"0.2.0\"")
    LibGit2.with(LibGit2.GitRepo(pkgdir)) do repo
        LibGit2.add!(repo, "*")
        LibGit2.commit(repo, "tag v0.2.0")
    end
    Pkg.activate()
    PkgDev.Registry.register(registry_path, joinpath(pkgs, "TheFirst"))
    Pkg.update()
    @test Pkg.installed()["TheFirst"] == v"0.2.0"
    Pkg.rm("TheFirst")
    pkg"add TheFirst@0.1.0"
    @test Pkg.installed()["TheFirst"] == v"0.1.0"
    Pkg.rm("TheFirst")
     # Add a new package that depends on TheFirst
    pkgdir = joinpath(pkgs, "TheSecond")
    PkgDev.generate(pkgdir, "MIT")
    # for testing
    cd(pkgdir) do
        run(`git remote remove origin`)
        run(`git remote add origin $pkgdir`)
    end
    Pkg.activate(pkgdir)
    Pkg.add("UUIDs")
    Pkg.add("TheFirst")
     # Add a compat to TheFirst
    proj = joinpath(pkgdir, "Project.toml")
    p = Pkg.Types.parse_toml(proj)
    p["compat"]["TheFirst"] = "0.1.0"
    open(proj, "w") do io
        Pkg.TOML.print(io, p)
    end
    LibGit2.with(LibGit2.GitRepo(joinpath(pkgs, "TheSecond"))) do repo
        LibGit2.add!(repo, "*")
        LibGit2.commit(repo, "tag v0.1.0")
    end
    Pkg.activate()
    PkgDev.Registry.register(registry_path, joinpath(pkgs, "TheSecond"))
    Pkg.add("TheSecond")
    @test Pkg.installed()["TheSecond"] == v"0.1.0"
    @test Pkg.API.__installed(PKGMODE_MANIFEST)["TheFirst"] == v"0.1.0"
end end

end # module
