module Entry

import Base: thispatch, nextpatch, nextminor, nextmajor, check_new_version
using Pkg, LibGit2
using Nullables
import ..PkgDev
import ..PkgDev.GitHub
using ..PkgDev: getrepohttpurl, PkgDevError

function pull_request(dir::AbstractString; commit::AbstractString="", url::AbstractString="", branch::AbstractString="")
    with(LibGit2.GitRepo, dir) do repo
        if isempty(commit)
            commit = string(LibGit2.head_oid(repo))
        else
            !LibGit2.iscommit(commit, repo) && throw(PkgDevError("Cannot find pull commit: $commit"))
        end
        if isempty(url)
            url = LibGit2.getconfig(repo, "remote.origin.url", "")
        end
        force_branch = !isempty(branch)
        if !force_branch
            branch = "pull-request/$(commit[1:8])"
        end

        m = match(LibGit2.GITHUB_REGEX, url)
        m === nothing && throw(PkgDevError("not a GitHub repo URL, can't make a pull request: $url"))
        owner, owner_repo = m.captures[2:3]
        user = GitHub.user()
        @info("Forking $owner/$owner_repo to $user")
        response = GitHub.fork(owner,owner_repo)
        fork = response["clone_url"]
        @info("Pushing changes as branch $branch")
        refspecs = ["HEAD:refs/heads/$branch"]  # workaround for $commit:refs/heads/$branch
        fork, payload = push_url_and_credentials(fork)
        LibGit2.push(repo, remoteurl=fork, refspecs=refspecs, force=force_branch, payload=payload)
        pr_url = "$(response["html_url"])/compare/$branch"
        @info("To create a pull-request, open:\n\n  $pr_url\n")
    end
end

function submit(pkg::AbstractString, registry::AbstractString, commit::AbstractString="")

    urlpath = Pkg.dir("METADATA",pkg,"url")
    url = ispath(urlpath) ? readchomp(urlpath) : ""
    pull_request(PkgDev.dir(pkg), commit=commit, url=url)
end

function push_url_and_credentials(url)
    payload = Nullable{LibGit2.AbstractCredentials}()
    m = match(LibGit2.GITHUB_REGEX,url)
    if m !== nothing
        url = "https://github.com/$(m.captures[1]).git"
        payload = GitHub.credentials()
    end
    url, payload
end

function publish(branch::AbstractString, prbranch::AbstractString="")
    tags = Dict{String,Vector{String}}()
    metapath = Pkg.dir("METADATA")
    with(LibGit2.GitRepo, metapath) do repo
        LibGit2.branch(repo) == branch ||
            throw(PkgDevError("METADATA must be on $branch to publish changes"))
        LibGit2.fetch(repo)

        ahead_remote, ahead_local = LibGit2.revcount(repo, "origin/$branch", branch)
        rcount = min(ahead_remote, ahead_local)
        ahead_remote - rcount > 0 && throw(PkgDevError("METADATA is behind origin/$branch – run `Pkg.update()` before publishing"))
        ahead_local - rcount == 0 && throw(PkgDevError("There are no METADATA changes to publish"))

        # get changed files
        for path in LibGit2.diff_files(repo, "origin/$branch", LibGit2.Consts.HEAD_FILE)
            m = match(r"^(.+?)/versions/([^/]+)/sha1$", path)
            m !== nothing && occursin(Base.VERSION_REGEX, m.captures[2]) || continue
            pkg, ver = m.captures; ver = VersionNumber(ver)
            sha1 = readchomp(joinpath(metapath,path))
            try
                old = LibGit2.content(LibGit2.GitBlob(repo, "origin/$branch:$path"))
                if old != sha1
                    throw(PkgDevError("$pkg v$ver SHA1 changed in METADATA – refusing to publish"))
                end
            catch e
                if !(e isa LibGit2.GitError && e.code == LibGit2.Error.ENOTFOUND)
                    rethrow(e)
                end
            end

            with(LibGit2.GitRepo, PkgDev.dir(pkg)) do pkg_repo
                tag_name = "v$ver"
                tag_commit = LibGit2.revparseid(pkg_repo, "$(tag_name)^{commit}")
                LibGit2.iszero(tag_commit) || string(tag_commit) == sha1 || return false
                haskey(tags,pkg) || (tags[pkg] = String[])
                push!(tags[pkg], tag_name)
                return true
            end || throw(PkgDevError("$pkg v$ver is incorrectly tagged – $sha1 expected"))
        end
        isempty(tags) && @info("No new package versions to publish")
        @info("Validating METADATA")
        check_metadata(Set(keys(tags)))
    end

    for pkg in sort!(collect(keys(tags)))
        with(LibGit2.GitRepo, PkgDev.dir(pkg)) do pkg_repo
            forced = String[]
            unforced = String[]
            for tag in tags[pkg]
                ver = VersionNumber(tag)
                push!(isrewritable(ver) ? forced : unforced, tag)
            end
            remoteurl, payload = push_url_and_credentials(
                LibGit2.url(LibGit2.get(LibGit2.GitRemote, pkg_repo, "origin")))
            if !isempty(forced)
                @info("Pushing $pkg temporary tags: ", join(forced,", "))
                LibGit2.push(pkg_repo, remote="origin", remoteurl=remoteurl, force=true,
                             refspecs=["refs/tags/$tag:refs/tags/$tag" for tag in forced],
                             payload=payload)
            end
            if !isempty(unforced)
                @info("Pushing $pkg permanent tags: ", join(unforced,", "))
                LibGit2.push(pkg_repo, remote="origin", remoteurl=remoteurl,
                             refspecs=["refs/tags/$tag:refs/tags/$tag" for tag in unforced],
                             payload=payload)
            end
        end
    end
    @info("Submitting METADATA changes")
    pull_request(metapath, branch=prbranch)
end

function write_tag_metadata(repo::LibGit2.GitRepo, pkg::AbstractString, ver::VersionNumber, commit::AbstractString, force::Bool=false)
    pkgdir = PkgDev.dir(pkg)
    content = with(LibGit2.GitRepo, pkgdir) do pkg_repo
        LibGit2.content(LibGit2.GitBlob(pkg_repo, "$commit:REQUIRE"))
    end
    reqs = content !== nothing ? Pkg.Reqs.read(split(content, '\n', keep=false)) : Pkg.Reqs.Line[]
    cd(Pkg.dir("METADATA")) do
        # work around julia#18724 and PkgDev#28
        d = join([pkg, "versions", string(ver)], '/')
        mkpath(d)
        sha1file = join([d, "sha1"], '/')
        if !force && ispath(sha1file)
            current = readchomp(sha1file)
            current == commit ||
                throw(PkgDevError("$pkg v$ver is already registered as $current, bailing"))
        end
        open(io->println(io,commit), sha1file, "w")
        LibGit2.add!(repo, sha1file)
        reqsfile = join([d, "requires"], '/')
        if isempty(reqs)
            ispath(reqsfile) && LibGit2.remove!(repo, reqsfile)
        else
            Pkg.Reqs.write(reqsfile,reqs)
            LibGit2.add!(repo, reqsfile)
        end
    end
    return nothing
end

function register(pkgdir::AbstractString, registrypath::AbstractString, url::AbstractString="")
    isempty(pkgdir) && throw(PkgDevError("$pkg does not exist"))
    metapath = Pkg.dir("METADATA")
    ispath(pkgdir, ".git") || throw(PkgDevError("$pkg is not a git repo"))
    isfile(metapath, pkg, "url") && throw(PkgDevError("$pkg already registered"))
    LibGit2.transact(LibGit2.GitRepo(metapath)) do repo
        # Get versions from package repo
        versions = with(LibGit2.GitRepo, pkgdir) do pkg_repo
            tags = filter(t->startswith(t,"v"), LibGit2.tag_list(pkg_repo))
            filter!(tag->occursin(Base.VERSION_REGEX, tag), tags)
            Dict(
                VersionNumber(tag) => string(LibGit2.revparseid(pkg_repo, "$tag^{commit}"))
                for tag in tags
            )
        end
        # Register package url in METADATA
        cd(metapath) do
            @info("Registering $pkg at $url")
            mkdir(pkg)
            # work around julia#18724 and PkgDev#28
            path = join([pkg, "url"], '/')
            open(io->println(io,url), path, "w")
            LibGit2.add!(repo, path)
        end
        # Register package version in METADATA
        vers = sort!(collect(keys(versions)))
        for ver in vers
            @info("Tagging $pkg v$ver")
            write_tag_metadata(repo, pkg,ver,versions[ver])
        end
        # Commit changes in METADATA
        if LibGit2.isdirty(repo)
            @info("Committing METADATA for $pkg")
            msg = "Register $pkg [$url]"
            if !isempty(versions)
                msg *= ": $(join(map(v->"v$v", vers),", "))"
            end
            LibGit2.commit(repo, msg)
        else
            @info("No METADATA changes to commit")
        end
    end
    return
end

function register(pkg::AbstractString)
    pkgdir = PkgDev.dir(pkg)
    isempty(pkgdir) && throw(PkgDevError("$pkg does not exist"))
    url = ""
    try
        url = LibGit2.getconfig(pkgdir, "remote.origin.url", "")
    catch err
        throw(PkgDevError("$pkg: $err"))
    end
    !isempty(url) || throw(PkgDevError("$pkg: no URL configured"))
    register(pkg, Pkg.Cache.normalize_url(url))
end

function isrewritable(v::VersionNumber)
    thispatch(v)==v"0" ||
    length(v.prerelease)==1 && isempty(v.prerelease[1]) ||
    length(v.build)==1 && isempty(v.build[1])
end

function tag(pkg::AbstractString; force::Bool=false, commitish::AbstractString="HEAD")
    pkgdir = PkgDev.dir(pkg)
    ispath(pkgdir,".git") || throw(PkgDevError("$pkg is not a git repo"))
    metapath = Pkg.dir("METADATA")
    with(LibGit2.GitRepo,metapath) do repo
        LibGit2.isdirty(repo, pkg) && throw(PkgDevError("METADATA/$pkg is dirty – commit or stash changes to tag"))
    end
    with(LibGit2.GitRepo, pkgdir) do repo
        LibGit2.isdirty(repo) && throw(PkgDevError("$pkg is dirty – commit or stash changes to tag"))
        commit = string(LibGit2.revparseid(repo, commitish))


        urlfile = joinpath(metapath,pkg,"url")
        registered = isfile(urlfile)

        if registered
            avail = Pkg.cd(Pkg.Read.available, pkg)
            existing = [VersionNumber(x) for x in keys(avail)]
            ancestors = filter(v->LibGit2.is_ancestor_of(avail[v].sha1, commit, repo), existing)
        else
            tags = filter(t->startswith(t,"v"), LibGit2.tag_list(repo))
            filter!(tag->occursin(Base.VERSION_REGEX, tag), tags)
            existing = [VersionNumber(x) for x in tags]
            filter!(tags) do tag
                sha1 = string(LibGit2.revparseid(repo, "$tag^{commit}"))
                LibGit2.is_ancestor_of(sha1, commit, repo)
            end
            ancestors = [VersionNumber(x) for x in tags]
        end
        sort!(existing)
        if !force
            isrewritable(ver) && filter!(v->v!=ver,existing)
            check_new_version(existing,ver)
        end
        # TODO: check that SHA1 isn't the same as another version
        @info("Tagging $pkg v$ver")
        LibGit2.tag_create(repo, "v$ver", commit,
                           msg=(!isrewritable(ver) ? "$pkg v$ver [$(commit[1:10])]" : ""),
                           force=(force || isrewritable(ver)) )
        registered || return
        try
            LibGit2.transact(LibGit2.GitRepo(metapath)) do repo
                write_tag_metadata(repo, pkg, ver, commit, force)
                if LibGit2.isdirty(repo)
                    @info("Committing METADATA for $pkg")
                    # Convert repo url into proper http url
                    repourl = getrepohttpurl(readchomp(urlfile))
                    tagmsg = "Tag $pkg v$ver [$repourl]"
                    prev_ver_idx = isa(ver, Symbol) ? 0 : coalesce(findlast(v -> v < ver, existing), 0)
                    if prev_ver_idx != 0
                        prev_ver = string(existing[prev_ver_idx])
                        prev_sha = readchomp(joinpath(metapath,pkg,"versions",prev_ver,"sha1"))
                        if occursin(LibGit2.GITHUB_REGEX, repourl)
                            tagmsg *= "\n\nDiff vs v$prev_ver: $repourl/compare/$prev_sha...$commit"
                        end
                    end
                    LibGit2.commit(repo, tagmsg)
                else
                    @info("No METADATA changes to commit")
                end
            end
        catch
            LibGit2.tag_delete(repo, "v$ver")
            rethrow()
        end
    end
    return
end

# TODO
function check_registry end


end
