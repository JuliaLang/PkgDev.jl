module Registry

import Base: thispatch, nextpatch, nextminor, nextmajor, check_new_version
using Pkg, LibGit2
import ..PkgDev
import ..PkgDev.GitHub
using ..PkgDev: getrepohttpurl, PkgDevError

import UUIDs

import Pkg.TOML, Pkg.Operations, Pkg.API
using Pkg.Types

function write_toml(f::Function, names::String...)
    path = joinpath(names...) * ".toml"
    mkpath(dirname(path))
    open(path, "w") do io
        f(io)
    end
end

function create_registry(path; repo::Union{Nothing, String} = nothing, uuid = UUIDs.uuid1(), description = nothing)
    isdir(path) && error("$(abspath(path)) already exists")
    mkpath(path)
    write_mainfile(path, uuid, repo, description)
    LibGit2.with(LibGit2.init(path)) do repo
        LibGit2.add!(repo, "*")
        LibGit2.commit(repo, "initial commit for registry $(basename(path))")
    end
    return
end

function write_mainfile(path, uuid, repo, description)
    d = Dict{String, Any}()
    d["name"] = basename(path)
    d["uuid"] = string(uuid)
    if repo !== nothing
        d["repo"]= repo
    end
    if description !== nothing
        d["description"] = description
    end
    write_mainfile(path, d)
end

is_stdlib(ctx::Context, uuid::UUID) = haskey(ctx.stdlibs, uuid)

function write_mainfile(path::String, data::Dict)
    open(joinpath(path, "Registry.toml"), "w") do io
        println(io, "name = ", repr(data["name"]))
        println(io, "uuid = ", repr(data["uuid"]))
        if haskey(data, "repo")
            println(io, "repo = ", repr(data["repo"]))
        end
        println(io)

        if haskey(data, "description")
            print(io, """
            description = \"\"\"
            $(data["description"])\"\"\"
            """
            )
        end

        println(io)
        println(io, "[packages]")
        if haskey(data, "packages")
            for (uuid, data) in sort!(collect(data["packages"]), by=first)
                println(io, uuid, " = { name = ", repr(data["name"]), ", path = ", repr(data["path"]), " }")
            end
        end
    end
end

struct PackageReg
    uuid::UUID
    name::String
    url::Union{String, Nothing}
    version::VersionNumber
    git_tree_sha::SHA1
    deps::Dict{UUID, VersionSpec}
end

const JULIA_UUID = UUID("1222c4b2-2114-5bfd-aeef-88e4692bbb3e")

function collect_package_info(pkgpath::String; url, commit)
    pkgpath = abspath(pkgpath)
    if !isdir(pkgpath)
        pkgerror("directory $(repr(pkgpath)) not found")
    end
    if !isdir(joinpath(pkgpath, ".git"))
        pkgerror("can only register git repositories as packages")
    end
    project_file = projectfile_path(pkgpath)
    if project_file === nothing
        pkgerror("package needs a \"[Julia]Project.toml\" file")
    end
    local git_tree_sha
    LibGit2.with(LibGit2.GitRepo(pkgpath)) do repo
        if commit == nothing
            if LibGit2.isdirty(repo)
                pkgerror("git repo at $(repr(pkgpath)) is dirty")
            end
            commit = LibGit2.head(repo)
        end
        git_tree_sha = begin
            LibGit2.with(LibGit2.peel(LibGit2.GitTree, commit)) do tree
                SHA1(string(LibGit2.GitHash(tree)))
            end
        end
    end
    if url === nothing
        try
            url = LibGit2.getconfig(pkgpath, "remote.origin.url", "")
        catch err
            pkgerror("$pkg: $err")
        end
    end

    f = project_file
    entry = joinpath(dirname(f), "src", "ads.jl")

    project = read_package(project_file)
    if !haskey(project, "version")
        pkgerror("project file did not contain a version entry")
    end
    vers = VersionNumber(project["version"])
    vers = VersionNumber(vers.major, vers.minor, vers.patch)
    name = project["name"]
    uuid = UUID(project["uuid"])

    name_uuid = Dict{String, UUID}()
    deps = Dict{UUID, VersionSpec}()
    deps[JULIA_UUID] = VersionSpec() # every package depends on julia
    for (pkg, dep_uuid) in project["deps"]
        name_uuid[pkg] = UUID(dep_uuid)
        deps[UUID(dep_uuid)] = VersionSpec()
    end

    for (pkg, verspec) in get(project, "compat", [])
        if pkg == "julia"
            dep_uuid = JULIA_UUID
        else
            if !haskey(name_uuid, pkg)
                pkgerror("package $pkg in compat section does not exist in deps section")
            end
            dep_uuid = name_uuid[pkg]
        end
        deps[dep_uuid] = Types.semver_spec(verspec)
    end

    return PackageReg(
        uuid,
        name,
        url,
        vers,
        git_tree_sha,
        deps
    )
end

register(registry::String, pkgpath; commit, url) =
    register(registry, collect_package_info(pkgpath; url=url, commit=commit); registering_new=true)
tag(registry::String, pkgpath; commit) =
    register(registry, collect_package_info(pkgpath; url=nothing, commit=commit); registering_new=false)

function register(registry::String, pkg::PackageReg; registering_new::Bool)
    !isdir(registry) && error(abspath(registry), " does not exist")
    registry_main_file = joinpath(registry, "Registry.toml")
    !isfile(registry_main_file) && error(abspath(registry_main_file), " does not exist")
    registry_data = TOML.parsefile(joinpath(registry, "Registry.toml"))

    registry_packages = get(registry_data, "packages", Dict{String, Any}())

    bin = string(first(pkg.name))

    if haskey(registry_packages, string(pkg.uuid))
       registering_new == false || pkgerror("package $(pkg.name) with uuid $(pkg.uuid) already registered")
       reldir = registry_packages[string(pkg.uuid)]["path"]
    else
        registering_new == true || pkgerror("package $(pkg.name) with uuid $(pkg.uuid) not registered")
        pkg.url === nothing && pkgerror("no URL configured for package")
        binpath = joinpath(registry, bin)
        mkpath(binpath)
        # store the package in $name__$i where i is the no. of pkgs with the same name
        # unless i == 0, then store in $name
        candidates = filter(x -> startswith(x, pkg.name), readdir(binpath))
        r = Regex("$(pkg.name)(__)?[0-9]*?\$")
        offset = count(x -> occursin(r, x), candidates)
        if offset == 0
            reldir = joinpath(string(first(pkg.name)), pkg.name)
        else
            reldir = joinpath(string(first(pkg.name)), "$(pkg.name)__$(offset+1)")
        end
    end

    registry_packages[string(pkg.uuid)] = Dict("name" => pkg.name, "path" => reldir)
    pkg_registry_path = joinpath(registry, reldir)

    LibGit2.transact(LibGit2.GitRepo(registry)) do repo
        mkpath(pkg_registry_path)
        for f in ("Versions.toml", "Deps.toml", "Compat.toml")
            isfile(joinpath(pkg_registry_path, f)) || touch(joinpath(pkg_registry_path, f))
        end

        version_data = Operations.load_versions(pkg_registry_path)
        if haskey(version_data, pkg.version)
            pkgerror("version $(pkg.version) already registered")
        end
        version_data[pkg.version] = pkg.git_tree_sha

        ctx = Context()
        for (uuid, v) in pkg.deps
            if !(is_stdlib(ctx, uuid) || string(uuid) in keys(registry_packages) || uuid == JULIA_UUID)
                pkgerror("dependency with uuid $(uuid) not an stdlib nor registered package")
            end
        end

        deps_data = Operations.load_package_data_raw(UUID, joinpath(pkg_registry_path, "Deps.toml"))
        compat_data = Operations.load_package_data_raw(VersionSpec, joinpath(pkg_registry_path, "Compat.toml"))

        new_deps = Dict{String, Any}()
        new_compat = Dict{String, Any}()
        for (uuid, v) in pkg.deps
            if uuid == JULIA_UUID
                new_compat["julia"] = v
                # We don't put julia in deps
            elseif is_stdlib(ctx, uuid)
                name = ctx.stdlibs[uuid]
                new_deps[name] = uuid
            else
                name = registry_packages[string(uuid)]["name"]
                new_compat[name] = v
                new_deps[name] = uuid
            end
        end
        deps_data[VersionRange(pkg.version)] = new_deps
        compat_data[VersionRange(pkg.version)] = new_compat

        # TODO: compression

        # Package.toml
        write_toml(joinpath(pkg_registry_path, "Package")) do io
            println(io, "name = ", repr(pkg.name))
            println(io, "uuid = ", repr(string(pkg.uuid)))
            println(io, "repo = ", repr(pkg.url))
        end

        # Versions.toml
        versionfile = joinpath(pkg_registry_path, "Versions.toml")
        isfile(versionfile) || touch(versionfile)
        write_toml(joinpath(pkg_registry_path, "Versions")) do io
            for (i, (ver, v)) in enumerate(sort!(collect(version_data), by=first))
                i > 1 && println(io)
                println(io, "[", toml_key(string(ver)), "]")
                println(io, "git-tree-sha1 = ", repr(string(pkg.git_tree_sha)))
            end
        end

        function write_version_data(f::String, d::Dict)
            write_toml(f) do io
                for (i, (ver, v)) in enumerate(sort!(collect(d), lt = Pkg.Types.isless_ll,
                                                                 by=x->first(x).lower))
                    i > 1 && println(io)
                    println(io, "[", toml_key(string(ver)), "]")
                    for (key, val) in collect(v) # TODO sort?
                        println(io, key, " = \"$val\"")
                    end
                end
            end
        end

        # Compat.toml
        write_version_data(joinpath(pkg_registry_path, "Compat"), compat_data)

        # Deps.toml
        write_version_data(joinpath(pkg_registry_path, "Deps"), deps_data)

        # Registry.toml
        if registering_new
            write_mainfile(joinpath(registry), registry_data)
            LibGit2.add!(repo, "Registry.toml")
        end
        LibGit2.add!(repo, reldir)
        # Commit it
        prefix = registering_new ? "Register" : "Tag v$(pkg.version)"
        LibGit2.commit(repo, "$prefix $(pkg.name) [$(pkg.url)]")
    end
    return
end


toml_key(str::String) = occursin(r"[^\w-]", str) ? repr(str) : str
toml_key(strs::String...) = join(map(toml_key, [strs...]), '.')


#=
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
        response = GitHub.fork(owner, owner_repo)
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

=#


end
