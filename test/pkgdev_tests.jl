@testitem "git URL parsing" begin
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

@testitem "https_url_from_git_url" begin
    # An http(s) URL is handed through untouched, so that the URL recorded in a
    # registry for an already-registered package does not change.
    @test PkgDev.https_url_from_git_url("https://github.com/JuliaLang/PkgDev.jl.git") == "https://github.com/JuliaLang/PkgDev.jl.git"
    @test PkgDev.https_url_from_git_url("https://github.com/JuliaLang/PkgDev.jl") == "https://github.com/JuliaLang/PkgDev.jl"

    # ssh spellings are converted to the canonical https form.
    @test PkgDev.https_url_from_git_url("git@github.com:JuliaLang/PkgDev.jl.git") == "https://github.com/JuliaLang/PkgDev.jl.git"
    @test PkgDev.https_url_from_git_url("git@github.com:JuliaLang/PkgDev.jl") == "https://github.com/JuliaLang/PkgDev.jl.git"
    @test PkgDev.https_url_from_git_url("ssh://git@github.com/JuliaLang/PkgDev.jl.git") == "https://github.com/JuliaLang/PkgDev.jl.git"
end

@testitem "uses_ssh_transport" begin
    @test PkgDev.uses_ssh_transport("git@github.com:JuliaLang/PkgDev.jl.git")
    @test PkgDev.uses_ssh_transport("ssh://git@github.com/JuliaLang/PkgDev.jl.git")
    @test !PkgDev.uses_ssh_transport("https://github.com/JuliaLang/PkgDev.jl.git")
    @test !PkgDev.uses_ssh_transport("http://github.com/JuliaLang/PkgDev.jl.git")

    @test PkgDev.ssh_url_from_repo("github.com", "JuliaLang/PkgDev.jl") == "git@github.com:JuliaLang/PkgDev.jl.git"
end
