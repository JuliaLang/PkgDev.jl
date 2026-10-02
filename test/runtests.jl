using PkgDev
using Test

@testset "PkgDev" begin

@testset "compute_tag_versions" begin
    # Default: strip the -DEV suffix, no bump.
    @test PkgDev.compute_tag_versions(v"1.2.3-DEV", nothing) == (v"1.2.3", v"1.2.4-DEV")

    # :patch on a -DEV version also just strips.
    @test PkgDev.compute_tag_versions(v"1.2.3-DEV", :patch) == (v"1.2.3", v"1.2.4-DEV")

    # :patch on a released version bumps.
    @test PkgDev.compute_tag_versions(v"1.2.3", :patch) == (v"1.2.4", v"1.2.5-DEV")

    # :minor and :major bump and zero the lower components.
    @test PkgDev.compute_tag_versions(v"1.2.3-DEV", :minor) == (v"1.3.0", v"1.3.1-DEV")
    @test PkgDev.compute_tag_versions(v"1.2.3-DEV", :major) == (v"2.0.0", v"2.0.1-DEV")

    # A -DEV version that already is the requested release just strips the suffix,
    # rather than bumping past it.
    @test PkgDev.compute_tag_versions(v"1.3.0-DEV", :minor) == (v"1.3.0", v"1.3.1-DEV")
    @test PkgDev.compute_tag_versions(v"2.0.0-DEV", :major) == (v"2.0.0", v"2.0.1-DEV")

    # ... but only when every lower component is already zero.
    @test PkgDev.compute_tag_versions(v"1.2.0-DEV", :major) == (v"2.0.0", v"2.0.1-DEV")
    @test PkgDev.compute_tag_versions(v"1.0.3-DEV", :major) == (v"2.0.0", v"2.0.1-DEV")

    # A released (non -DEV) version always bumps.
    @test PkgDev.compute_tag_versions(v"1.2.0", :minor) == (v"1.3.0", v"1.3.1-DEV")
    @test PkgDev.compute_tag_versions(v"2.0.0", :major) == (v"3.0.0", v"3.0.1-DEV")

    # An explicit version is used as-is.
    @test PkgDev.compute_tag_versions(v"1.2.3-DEV", v"5.6.7") == (v"5.6.7", v"5.6.8-DEV")

    # Without an explicit version the current version must be x.y.z-DEV.
    @test_throws ErrorException PkgDev.compute_tag_versions(v"1.2.3", nothing)
    @test_throws ErrorException PkgDev.compute_tag_versions(v"1.2.3-rc1", nothing)

    @test_throws ErrorException PkgDev.compute_tag_versions(v"1.2.3-DEV", :banana)
end


@testset "git URL parsing" begin
    # https, with and without the .git suffix and a trailing slash.
    @test PkgDev.get_repo_onwer_from_url("https://github.com/JuliaLang/PkgDev.jl") == "JuliaLang/PkgDev.jl"
    @test PkgDev.get_repo_onwer_from_url("https://github.com/JuliaLang/PkgDev.jl.git") == "JuliaLang/PkgDev.jl"
    @test PkgDev.get_repo_onwer_from_url("https://github.com/JuliaLang/PkgDev.jl/") == "JuliaLang/PkgDev.jl"
    @test PkgDev.get_repo_onwer_from_url("https://github.com/JuliaLang/PkgDev.jl.GIT") == "JuliaLang/PkgDev.jl"

    # scp-like ssh syntax, which is what `git clone git@...` leaves behind.
    @test PkgDev.get_repo_onwer_from_url("git@github.com:JuliaLang/PkgDev.jl.git") == "JuliaLang/PkgDev.jl"
    @test PkgDev.get_repo_onwer_from_url("git@github.com:JuliaLang/PkgDev.jl") == "JuliaLang/PkgDev.jl"

    # ssh:// URLs.
    @test PkgDev.get_repo_onwer_from_url("ssh://git@github.com/JuliaLang/PkgDev.jl.git") == "JuliaLang/PkgDev.jl"

    @test_throws ErrorException PkgDev.get_repo_onwer_from_url("not a url")
    @test_throws ErrorException PkgDev.get_repo_onwer_from_url("https://github.com/")
    # Not of the form owner/repo.
    @test_throws ErrorException PkgDev.get_repo_onwer_from_url("https://github.com/JuliaLang/PkgDev.jl/tree/main")

    @test PkgDev.parse_git_url("ssh://git@github.example.com:2222/o/r.git").host == "github.example.com"
    @test PkgDev.parse_git_url("git@github.com:o/r.git").protocol === nothing
end

@testset "https_url_from_git_url" begin
    # An http(s) URL is handed through untouched, so that the URL recorded in a
    # registry for an already-registered package does not change.
    @test PkgDev.https_url_from_git_url("https://github.com/JuliaLang/PkgDev.jl.git") == "https://github.com/JuliaLang/PkgDev.jl.git"
    @test PkgDev.https_url_from_git_url("https://github.com/JuliaLang/PkgDev.jl") == "https://github.com/JuliaLang/PkgDev.jl"

    # ssh spellings are converted to the canonical https form.
    @test PkgDev.https_url_from_git_url("git@github.com:JuliaLang/PkgDev.jl.git") == "https://github.com/JuliaLang/PkgDev.jl.git"
    @test PkgDev.https_url_from_git_url("git@github.com:JuliaLang/PkgDev.jl") == "https://github.com/JuliaLang/PkgDev.jl.git"
    @test PkgDev.https_url_from_git_url("ssh://git@github.com/JuliaLang/PkgDev.jl.git") == "https://github.com/JuliaLang/PkgDev.jl.git"
end

@testset "uses_ssh_transport" begin
    @test PkgDev.uses_ssh_transport("git@github.com:JuliaLang/PkgDev.jl.git")
    @test PkgDev.uses_ssh_transport("ssh://git@github.com/JuliaLang/PkgDev.jl.git")
    @test !PkgDev.uses_ssh_transport("https://github.com/JuliaLang/PkgDev.jl.git")
    @test !PkgDev.uses_ssh_transport("http://github.com/JuliaLang/PkgDev.jl.git")

    @test PkgDev.ssh_url_from_repo("github.com", "JuliaLang/PkgDev.jl") == "git@github.com:JuliaLang/PkgDev.jl.git"
end

end
