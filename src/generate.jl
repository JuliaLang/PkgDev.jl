module Generate

import Base.LibGit2, Base.Pkg.Read, Base.Pkg.PkgError
importall Base.LibGit2
import ..PkgDev: readlicense, LICENSES

copyright_year() =  string(Dates.year(Dates.today()))
copyright_name(repo::GitRepo) = LibGit2.getconfig(repo, "user.name", "")
github_user() = LibGit2.getconfig("github.user", "")

function git_contributors(repo::GitRepo, n::Int=typemax(Int))
    contrib = Dict()
    for sig in LibGit2.authors(repo)
        if haskey(contrib, sig.email)
            contrib[sig.email][1] += 1
        else
            contrib[sig.email] = [1, sig.name]
        end
    end

    names = Dict()
    for (commits,name) in values(contrib)
        names[name] = get(names,name,0) + commits
    end
    names = sort!(collect(keys(names)),by=name->names[name],rev=true)
    length(names) <= n ? names : [names[1:n]; "et al."]
end

function package(
    pkg::AbstractString,
    license::AbstractString;
    force::Bool = false,
    authors::Union{AbstractString,Array} = "",
    years::Union{Int,AbstractString} = copyright_year(),
    user::AbstractString = github_user(),
    config::Dict = Dict(),
    path::AbstractString = Pkg.Dir.path(),
    travis::Bool = true,
    appveyor::Bool = true,
    coverage::Bool = true,
    document::Bool = true
)
    pkg_path = joinpath(path,pkg)
    isnew = !ispath(pkg_path)
    try
        repo = if isnew
            url = isempty(user) ? "" : "https://github.com/$user/$pkg.jl.git"
            Generate.init(pkg_path,url,config=config)
        else
            repo = GitRepo(pkg_path)
            if LibGit2.isdirty(repo)
                finalize(repo)
                throw(PkgError("$pkg is dirty – commit or stash your changes"))
            end
            repo
        end

        LibGit2.transact(repo) do repo
            if isempty(authors)
                authors = isnew ? copyright_name(repo) : git_contributors(repo,5)
            end

            files = [Generate.license(pkg_path,license,years,authors,
                         force=force),
                     Generate.readme(pkg_path,user,force=force,
                         coverage=coverage,document=document),
                     Generate.entrypoint(pkg_path,force=force),
                     Generate.tests(pkg_path,force=force,document=document),
                     Generate.require(pkg_path,force=force),
                     Generate.gitignore(pkg_path,force=force,document=document)]

            travis && push!(files,
                Generate.travis(pkg_path,force=force,coverage=coverage,
                    document=document))
            appveyor && push!(files, Generate.appveyor(pkg_path,force=force))
            coverage && push!(files, Generate.codecov(pkg_path,force=force))
            document && push!(files,
                              Generate.document_make(pkg_path,user,force=force),
                              Generate.document_index(pkg_path,force=force),
                              Generate.tests_require(pkg_path,force=force))

            msg = """
            $pkg.jl $(isnew ? "generated" : "regenerated") files.

                license:  $license
                authors:  $(join(vcat(authors),", "))
                years:    $years
                user:     $user

            Julia Version $VERSION [$(Base.GIT_VERSION_INFO.commit_short)]
            """
            LibGit2.add!(repo, files..., flags = LibGit2.Consts.INDEX_ADD_FORCE)
            if isnew
                info("Committing $pkg generated files")
                LibGit2.commit(repo, msg)
            elseif LibGit2.isdirty(repo)
                LibGit2.remove!(repo, files...)
                info("Regenerated files left unstaged, use `git add -p` to select")
                open(io->print(io,msg), joinpath(LibGit2.gitdir(repo),"MERGE_MSG"), "w")
            else
                info("Regenerated files are unchanged")
            end
        end
    catch
        isnew && rm(pkg_path, recursive=true)
        rethrow()
    end
    return
end

function init(pkg::AbstractString, url::AbstractString=""; config::Dict=Dict())
    if !ispath(pkg)
        pkg_name = basename(pkg)
        info("Initializing $pkg_name repo: $pkg")
        repo = LibGit2.init(pkg)
        try
            with(GitConfig, repo) do cfg
                for (key,val) in config
                    LibGit2.set!(cfg, key, val)
                end
            end
            LibGit2.commit(repo, "initial empty commit")
        catch err
            throw(PkgError("Unable to initialize $pkg_name package: $err"))
        end
    else
        repo = GitRepo(pkg)
    end
    try
        if !isempty(url)
            info("Origin: $url")
            with(LibGit2.GitRemote, repo, "origin", url) do rmt
                LibGit2.save(rmt)
            end
            LibGit2.set_remote_url(repo, url)
        end
    end
    return repo
end

function genfile(f::Function, pkg::AbstractString, file::AbstractString, force::Bool=false)
    path = joinpath(pkg,file)
    if force || !ispath(path)
        info("Generating $file")
        mkpath(dirname(path))
        open(f, path, "w")
        return file
    end
    return ""
end

function license(pkg::AbstractString,
                 license::AbstractString,
                 years::Union{Int,AbstractString},
                 authors::Union{AbstractString,Array};
                 force::Bool=false)
    pkg_name = basename(pkg)
    file = genfile(pkg,"LICENSE.md",force) do io
        if !haskey(LICENSES, license)
            licenses = join(sort!(collect(keys(LICENSES)), by=lowercase), ", ")
            throw(PkgError("$license is not a known license choice, choose one of: $licenses."))
        end
        println(io, "The $pkg_name.jl package is licensed under the $(LICENSES[license]):")
        println(io)
        println(io, copyright(years,authors))
        lic=readlicense(license)
        for l in split(lic,['\n','\r'])
            println(io, "> ", l)
        end
    end
    !isempty(file) || info("License file exists, leaving unmodified; use `force=true` to overwrite")
    file
end

function readme(pkg::AbstractString, user::AbstractString=""; force::Bool=false,
                coverage::Bool=true, document::Bool=true)
    pkg_name = basename(pkg)
    genfile(pkg,"README.md",force) do io
        println(io, "# $pkg_name")
        isempty(user) && return
        url = "https://travis-ci.org/$user/$pkg_name.jl"
        println(io, "\n[![Build Status]($url.svg?branch=master)]($url)")
        appveyor_pkg_name = replace(pkg_name, ".", "-")
        appveyor_badge = "https://ci.appveyor.com/api/projects/status/github/$user/$pkg_name.jl?svg=true&branch=master"
        appveyor_link = "https://ci.appveyor.com/project/$user/$appveyor_pkg_name/branch/master"
        println(io, "\n[![Appveyor Status]($appveyor_badge.svg?branch=master)]($appveyor_link)")
        if coverage
            coveralls_badge = "https://coveralls.io/repos/$user/$pkg_name.jl/badge.svg?branch=master&service=github"
            coveralls_url = "https://coveralls.io/github/$user/$pkg_name.jl?branch=master"
            println(io, "\n[![Coverage Status]($coveralls_badge)]($coveralls_url)")
            codecov_badge = "http://codecov.io/github/$user/$pkg_name.jl/coverage.svg?branch=master"
            codecov_url = "http://codecov.io/github/$user/$pkg_name.jl?branch=master"
            println(io, "\n[![codecov.io]($codecov_badge)]($codecov_url)")
        end
        if document
            docs_stable_url = "https://$user.github.io/$pkg_name.jl/stable"
            docs_latest_url = "https://$user.github.io/$pkg_name.jl/latest"
            print(io, """

            ## Documentation

            - [**STABLE**]($docs_stable_url) &mdash; **most recently tagged version of the documentation.**
            - [**LATEST**]($docs_latest_url) &mdash; *in-development version of the documentation.*
            """)
        end
    end
end

function tests(pkg::AbstractString; force::Bool=false,document=true,
               copyright_name = "")
    pkg_name = basename(pkg)
    genfile(pkg,"test/runtests.jl",force) do io
        print(io, """
        using $pkg_name
        using Base.Test

        # write your own tests here
        @test 1 == 2
        """)

        if document
            print(io, """

            # run doctests
            makedocs(
                modules = [$pkg_name],
                format = :html,
                sitename = "$pkg_name.jl",
                pages = Any["Home" => "index.md"]
                root = joinpath(dirname(dirname(@__FILE__)), "docs")
                strict = true
            )
            """)
        end
    end
end

function versionfloor(ver::VersionNumber)
    # return "major.minor" for the most recent release version relative to ver
    # for prereleases with ver.minor == ver.patch == 0, return "major-" since we
    # don't know what the most recent minor version is for the previous major
    if isempty(ver.prerelease) || ver.patch > 0
        return string(ver.major, '.', ver.minor)
    elseif ver.minor > 0
        return string(ver.major, '.', ver.minor - 1)
    else
        return string(ver.major, '-')
    end
end

function require(pkg::AbstractString; force::Bool=false)
    genfile(pkg,"REQUIRE",force) do io
        print(io, """
        julia $(versionfloor(VERSION))
        """)
    end
end

function tests_require(pkg::AbstractString; force::Bool=false)
    genfile(pkg,"test/REQUIRE",force) do io
        print(io, """
        Documenter
        """)
    end
end

maybe_comment(dont_comment::Bool) = if dont_comment
    ""
else
    "#"
end

function travis(pkg::AbstractString; force::Bool=false, coverage::Bool=true,
                document::Bool=true)
    pkg_name = basename(pkg)
    c = maybe_comment(coverage)
    d = maybe_comment(document)
    genfile(pkg,".travis.yml",force) do io
        print(io, """
        # Documentation: http://docs.travis-ci.com/user/languages/julia/
        language: julia
        os:
          - linux
          - osx
        julia:
          - release
          - nightly
        notifications:
          email: false
        # uncomment the following lines to override the default test script
        #script:
        #  - if [[ -a .git/shallow ]]; then git fetch --unshallow; fi
        #  - julia -e 'Pkg.clone(pwd()); Pkg.build("$pkg_name"); Pkg.test("$pkg_name"; coverage=true)'
        $(c)after_success:
        $(c)  # push coverage results to Coveralls
        $(c)  - julia -e 'cd(Pkg.dir("$pkg_name")); Pkg.add("Coverage"); using Coverage; Coveralls.submit(Coveralls.process_folder())'
        $(c)  # push coverage results to Codecov
        $(c)  - julia -e 'cd(Pkg.dir("$pkg_name")); Pkg.add("Coverage"); using Coverage; Codecov.submit(Codecov.process_folder())'
        $(d)  # build documentation
        $(d)  - julia -e 'ENV["DOCUMENTER_DEBUG"] = "true"; cd(Pkg.dir("$pkg_name")); Pkg.add("Documenter"); include(joinpath("docs", "make.jl"))'
        """)
    end
end

function appveyor(pkg::AbstractString; force::Bool=false)
    pkg_name = basename(pkg)
    vf = versionfloor(VERSION)
    if vf[end] == '-' # don't know what previous release was
        vf = string(VERSION.major, '.', VERSION.minor)
        rel32 = "#  - JULIAVERSION: \"julialang/bin/winnt/x86/$vf/julia-$vf-latest-win32.exe\""
        rel64 = "#  - JULIAVERSION: \"julialang/bin/winnt/x64/$vf/julia-$vf-latest-win64.exe\""
    else
        rel32 = "  - JULIAVERSION: \"julialang/bin/winnt/x86/$vf/julia-$vf-latest-win32.exe\""
        rel64 = "  - JULIAVERSION: \"julialang/bin/winnt/x64/$vf/julia-$vf-latest-win64.exe\""
    end
    genfile(pkg,"appveyor.yml",force) do io
        print(io, """
        environment:
          matrix:
        $rel32
        $rel64
          - JULIAVERSION: "julianightlies/bin/winnt/x86/julia-latest-win32.exe"
          - JULIAVERSION: "julianightlies/bin/winnt/x64/julia-latest-win64.exe"

        branches:
          only:
            - master
            - /release-.*/

        notifications:
          - provider: Email
            on_build_success: false
            on_build_failure: false
            on_build_status_changed: false

        install:
        # Download most recent Julia Windows binary
          - ps: (new-object net.webclient).DownloadFile(
                \$("http://s3.amazonaws.com/"+\$env:JULIAVERSION),
                "C:\\projects\\julia-binary.exe")
        # Run installer silently, output to C:\\projects\\julia
          - C:\\projects\\julia-binary.exe /S /D=C:\\projects\\julia

        build_script:
        # Need to convert from shallow to complete for Pkg.clone to work
          - IF EXIST .git\\shallow (git fetch --unshallow)
          - C:\\projects\\julia\\bin\\julia -e "versioninfo();
              Pkg.clone(pwd(), \\"$pkg_name\\"); Pkg.build(\\"$pkg_name\\")"

        test_script:
          - C:\\projects\\julia\\bin\\julia -e "Pkg.test(\\"$pkg_name\\")"
        """)
    end
end

function codecov(pkg::AbstractString; force::Bool=false)
    genfile(pkg, ".codecov.yml", force) do io
        print(io, """
        comment: false
        """)
    end
end

function gitignore(pkg::AbstractString; force::Bool=false, document::Bool=true)
    genfile(pkg,".gitignore",force) do io
        print(io, """
        *.jl.cov
        *.jl.*.cov
        *.jl.mem
        """)

        if document
            print(io, """
            docs/build/
            docs/site/
            """)
        end
    end
end

function document_make(pkg::AbstractString,user::AbstractString="";
                       force::Bool=false)
    pkg_name = basename(pkg)
    genfile(pkg,"docs/make.jl",force) do io
        print(io, """
        using Documenter, $pkg_name

        # for successful deployment, make sure to
        # - add a gh-pages branch on github
        # - set up SSH deploy keys
        # see https://juliadocs.github.io/Documenter.jl/latest/man/hosting.html for further instructions
        deploydocs(
            repo = "github.com/$user/$pkg_name.jl.git",
            target = "build",
            deps = nothing,
            make = nothing
        )
        """)
    end
end

function document_index(pkg::AbstractString; force::Bool=false)
    pkg_name = basename(pkg)

    genfile(pkg,"docs/src/index.md",force) do io
        print(io, """
        # $pkg_name.jl

        ```@index
        ```

        ```@autodocs
        Modules = [$pkg_name]
        ```
        """)
    end
end

function entrypoint(pkg::AbstractString; force::Bool=false)
    pkg_name = basename(pkg)
    genfile(pkg,"src/$pkg_name.jl",force) do io
        print(io, """
        module $pkg_name

        # package code goes here

        end # module
        """)
    end
end

copyright(years::AbstractString, authors::AbstractString) = "> Copyright (c) $years: $authors."

function copyright(years::AbstractString, authors::Array)
    text = "> Copyright (c) $years:"
    for author in authors
        text *= "\n>  * $author"
    end
    return text
end

end # module
