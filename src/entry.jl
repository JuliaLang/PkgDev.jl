# This file is a part of Julia. License is MIT: http://julialang.org/license

module Entry

import Base: thispatch, nextpatch, nextminor, nextmajor, check_new_version
import Base.Pkg: Reqs, Read, Query, Resolve, PkgError
import Base.LibGit2
importall Base.LibGit2
using Base.Pkg.Types
import ..PkgDev
import ..PkgDev.GitHub


function pull_request(dir::AbstractString; commit::AbstractString="", url::AbstractString="", branch::AbstractString="")
    with(GitRepo, dir) do repo
        if isempty(commit)
            commit = string(LibGit2.head_oid(repo))
        else
            !LibGit2.iscommit(commit, repo) && throw(PkgError("Cannot find pull commit: $commit"))
        end
        if isempty(url)
            url = LibGit2.getconfig(repo, "remote.origin.url", "")
        end
        force_branch = !isempty(branch)
        if !force_branch
            branch = "pull-request/$(commit[1:8])"
        end

        m = match(LibGit2.GITHUB_REGEX, url)
        m === nothing && throw(PkgError("not a GitHub repo URL, can't make a pull request: $url"))
        owner, owner_repo = m.captures[2:3]
        user = GitHub.user()
        info("Forking $owner/$owner_repo to $user")
        response = GitHub.fork(owner,owner_repo)
        fork = response["clone_url"]
        info("Pushing changes as branch $branch")
        refspecs = ["HEAD:refs/heads/$branch"]  # workaround for $commit:refs/heads/$branch
        LibGit2.push(repo, remoteurl=fork, refspecs=refspecs, force=force_branch, payload=GitHub.credentials())
        pr_url = "$(response["html_url"])/compare/$branch"
        info("To create a pull-request, open:\n\n  $pr_url\n")
    end
end

function submit(pkg::AbstractString, commit::AbstractString="")
    urlpath = Pkg.dir("METADATA",pkg,"url")
    url = ispath(urlpath) ? readchomp(urlpath) : ""
    pull_request(PkgDev.dir(pkg), commit=commit, url=url)
end

function publish(branch::AbstractString, prbranch::AbstractString="")
    tags = Dict{ByteString,Vector{ASCIIString}}()
    metapath = Pkg.dir("METADATA")
    with(GitRepo, metapath) do repo
        LibGit2.branch(repo) == branch ||
            throw(PkgError("METADATA must be on $branch to publish changes"))
        LibGit2.fetch(repo)

        ahead_remote, ahead_local = LibGit2.revcount(repo, "origin/$branch", branch)
        rcount = min(ahead_remote, ahead_local)
        ahead_remote-rcount > 0 && throw(PkgError("METADATA is behind origin/$branch – run `Pkg.update()` before publishing"))
        ahead_local-rcount == 0 && throw(PkgError("There are no METADATA changes to publish"))

        # get changed files
        for path in LibGit2.diff_files(repo, "origin/$branch", LibGit2.Consts.HEAD_FILE)
            m = match(r"^(.+?)/versions/([^/]+)/sha1$", path)
            m !== nothing && ismatch(Base.VERSION_REGEX, m.captures[2]) || continue
            pkg, ver = m.captures; ver = convert(VersionNumber,ver)
            sha1 = readchomp(joinpath(metapath,path))
            old = LibGit2.cat(repo, LibGit2.GitBlob, "origin/$branch:$path")
            old !== nothing && old != sha1 && throw(PkgError("$pkg v$ver SHA1 changed in METADATA – refusing to publish"))
            with(GitRepo, PkgDev.dir(pkg)) do pkg_repo
                tag_name = "v$ver"
                tag_commit = LibGit2.revparseid(pkg_repo, "$(tag_name)^{commit}")
                LibGit2.iszero(tag_commit) || string(tag_commit) == sha1 || return false
                haskey(tags,pkg) || (tags[pkg] = ASCIIString[])
                push!(tags[pkg], tag_name)
                return true
            end || throw(PkgError("$pkg v$ver is incorrectly tagged – $sha1 expected"))
        end
        isempty(tags) && info("No new package versions to publish")
        info("Validating METADATA")
        check_metadata(Set(keys(tags)))
    end

    for pkg in sort!(collect(keys(tags)))
        with(GitRepo, PkgDev.dir(pkg)) do pkg_repo
            forced = ASCIIString[]
            unforced = ASCIIString[]
            for tag in tags[pkg]
                ver = convert(VersionNumber,tag)
                push!(isrewritable(ver) ? forced : unforced, tag)
            end
            if !isempty(forced)
                info("Pushing $pkg temporary tags: ", join(forced,", "))
                LibGit2.push(pkg_repo, remote="origin", force=true,
                             refspecs=["refs/tags/$tag:refs/tags/$tag" for tag in forced],
                             payload=GitHub.credentials())
            end
            if !isempty(unforced)
                info("Pushing $pkg permanent tags: ", join(unforced,", "))
                LibGit2.push(pkg_repo, remote="origin",
                             refspecs=["refs/tags/$tag:refs/tags/$tag" for tag in unforced],
                             payload=GitHub.credentials())
            end
        end
    end
    info("Submitting METADATA changes")
    pull_request(metapath, branch=prbranch)
end

function write_tag_metadata(repo::GitRepo, pkg::AbstractString, ver::VersionNumber, commit::AbstractString, force::Bool=false)
    pkgdir = PkgDev.dir(pkg)
    content = with(GitRepo, pkgdir) do pkg_repo
        LibGit2.cat(pkg_repo, LibGit2.GitBlob, "$commit:REQUIRE")
    end
    reqs = content !== nothing ? Reqs.read(split(content, '\n', keep=false)) : Reqs.Line[]
    cd("METADATA") do
        d = joinpath(pkg,"versions",string(ver))
        mkpath(d)
        sha1file = joinpath(d,"sha1")
        if !force && ispath(sha1file)
            current = readchomp(sha1file)
            current == commit ||
                throw(PkgError("$pkg v$ver is already registered as $current, bailing"))
        end
        open(io->println(io,commit), sha1file, "w")
        LibGit2.add!(repo, sha1file)
        reqsfile = joinpath(d,"requires")
        if isempty(reqs)
            ispath(reqsfile) && LibGit2.remove!(repo, reqsfile)
        else
            Reqs.write(reqsfile,reqs)
            LibGit2.add!(repo, reqsfile)
        end
    end
    return nothing
end

function register(pkg::AbstractString, url::AbstractString)
    pkgdir = PkgDev.dir(pkg)
    isempty(pkgdir) && throw(PkgError("$pkg does not exist"))
    metapath = Pkg.dir("METADATA")
    ispath(pkgdir,".git") || throw(PkgError("$pkg is not a git repo"))
    isfile(metapath,pkg,"url") && throw(PkgError("$pkg already registered"))
    LibGit2.transact(GitRepo(metapath)) do repo
        # Get versions from package repo
        versions = with(GitRepo, pkgdir) do pkg_repo
            tags = filter(t->startswith(t,"v"), LibGit2.tag_list(pkg_repo))
            filter!(tag->ismatch(Base.VERSION_REGEX,tag), tags)
            [
                convert(VersionNumber,tag) => string(LibGit2.revparseid(pkg_repo, "$tag^{commit}"))
                for tag in tags
            ]
        end
        # Register package url in METADATA
        cd(metapath) do
            info("Registering $pkg at $url")
            mkdir(pkg)
            path = joinpath(pkg,"url")
            open(io->println(io,url), path, "w")
            LibGit2.add!(repo, path)
        end
        # Register package version in METADATA
        vers = sort!(collect(keys(versions)))
        for ver in vers
            info("Tagging $pkg v$ver")
            write_tag_metadata(repo, pkg,ver,versions[ver])
        end
        # Commit changes in METADATA
        if LibGit2.isdirty(repo)
            info("Committing METADATA for $pkg")
            msg = "Register $pkg [$url]"
            if !isempty(versions)
                msg *= ": $(join(map(v->"v$v", vers),", "))"
            end
            LibGit2.commit(repo, msg)
        else
            info("No METADATA changes to commit")
        end
    end
    return
end

function register(pkg::AbstractString)
    pkgdir = PkgDev.dir(pkg)
    isempty(pkgdir) && throw(PkgError("$pkg does not exist"))
    url = ""
    try
        url = LibGit2.getconfig(pkgdir, "remote.origin.url", "")
    catch err
        throw(PkgError("$pkg: $err"))
    end
    !isempty(url) || throw(PkgError("$pkg: no URL configured"))
    register(pkg, LibGit2.normalize_url(url))
end

function isrewritable(v::VersionNumber)
    thispatch(v)==v"0" ||
    length(v.prerelease)==1 && isempty(v.prerelease[1]) ||
    length(v.build)==1 && isempty(v.build[1])
end

nextbump(v::VersionNumber) = isrewritable(v) ? v : nextpatch(v)

function tag(pkg::AbstractString, ver::Union{Symbol,VersionNumber}, force::Bool=false, commitish::AbstractString="HEAD")
    pkgdir = PkgDev.dir(pkg)
    ispath(pkgdir,".git") || throw(PkgError("$pkg is not a git repo"))
    metapath = Pkg.dir("METADATA")
    with(GitRepo,metapath) do repo
        LibGit2.isdirty(repo, pkg) && throw(PkgError("METADATA/$pkg is dirty – commit or stash changes to tag"))
    end
    with(GitRepo, pkgdir) do repo
        LibGit2.isdirty(repo) && throw(PkgError("$pkg is dirty – commit or stash changes to tag"))
        commit = string(LibGit2.revparseid(repo, commitish))
        urlfile = joinpath(metapath,pkg,"url")
        registered = isfile(urlfile)

        if !force
            if registered
                avail = Pkg.cd(Pkg.Read.available, pkg)
                existing = VersionNumber[keys(avail)...]
                ancestors = filter(v->LibGit2.is_ancestor_of(avail[v].sha1, commit, repo), existing)
            else
                tags = filter(t->startswith(t,"v"), Pkg.LibGit2.tag_list(repo))
                filter!(tag->ismatch(Base.VERSION_REGEX,tag), tags)
                existing = VersionNumber[tags...]
                filter!(tags) do tag
                    sha1 = string(LibGit2.revparseid(repo, "$tag^{commit}"))
                    LibGit2.is_ancestor_of(sha1, commit, repo)
                end
                ancestors = VersionNumber[tags...]
            end
            sort!(existing)
            if isa(ver,Symbol)
                prv = isempty(existing) ? v"0" :
                      isempty(ancestors) ? maximum(existing) : maximum(ancestors)
                ver = (ver == :bump ) ? nextbump(prv)  :
                      (ver == :patch) ? nextpatch(prv) :
                      (ver == :minor) ? nextminor(prv) :
                      (ver == :major) ? nextmajor(prv) :
                                        throw(PkgError("invalid version selector: $ver"))
            end
            isrewritable(ver) && filter!(v->v!=ver,existing)
            check_new_version(existing,ver)
        end
        # TODO: check that SHA1 isn't the same as another version
        info("Tagging $pkg v$ver")
        LibGit2.tag_create(repo, "v$ver", commit,
                           msg=(!isrewritable(ver) ? "$pkg v$ver [$(commit[1:10])]" : ""),
                           force=(force || isrewritable(ver)) )
        registered || return
        try
            LibGit2.transact(GitRepo(metapath)) do repo
                write_tag_metadata(repo, pkg, ver, commit, force)
                if LibGit2.isdirty(repo)
                    info("Committing METADATA for $pkg")
                    LibGit2.commit(repo, "Tag $pkg v$ver [$(readchomp(urlfile))]")
                else
                    info("No METADATA changes to commit")
                end
            end
        catch
            LibGit2.tag_delete(repo, "v$ver")
            rethrow()
        end
    end
    return
end

function check_metadata(pkgs::Set{ByteString} = Set{ByteString}())
    avail = Pkg.cd(Read.available)
    deps, conflicts = Query.dependencies(avail)

    for (dp,dv) in deps, (v,a) in dv, p in keys(a.requires)
        haskey(deps, p) || throw(PkgError("package $dp v$v requires a non-registered package: $p"))
    end

    problematic = Resolve.sanity_check(deps, pkgs)
    if !isempty(problematic)
        msg = "packages with unsatisfiable requirements found:\n"
        for (p, vn, rp) in problematic
            msg *= "    $p v$vn – no valid versions exist for package $rp\n"
        end
        throw(PkgError(msg))
    end
    return
end

end
