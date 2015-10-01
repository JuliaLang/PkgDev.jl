module PkgDev

export Entry, Generate

include("entry.jl")
include("generate.jl")

const cd = Pkg.Dir.cd

"""
    dir(pkg, [paths...])

Returns package `pkg` directory location through search. Additional `paths` are appended.
"""
function dir(pkg::AbstractString)
    pkgsrc = Base.find_in_path(pkg, Pkg.dir())
    pkgsrc === nothing && return ""
    abspath(dirname(pkgsrc), "..") |> realpath
end
dir(pkg::AbstractString, args...) = normpath(dir(pkg),args...)

"""
    register(pkg, [url])

Register `pkg` at the git URL `url`, defaulting to the configured origin URL of the git repo `Pkg.dir(pkg)`.
"""
register(pkg::AbstractString) = Entry.register(pkg)
register(pkg::AbstractString, url::AbstractString) = Entry.register(pkg,url)

"""
    tag(pkg, [ver, [commit]])

Tag `commit` as version `ver` of package `pkg` and create a version entry in `METADATA`. If not provided, `commit` defaults to the current commit of the `pkg` repo. If `ver` is one of the symbols `:patch`, `:minor`, `:major` the next patch, minor or major version is used. If `ver` is not provided, it defaults to `:patch`.
"""
tag(pkg::AbstractString, sym::Symbol=:patch) = cd(Entry.tag,pkg,sym)
tag(pkg::AbstractString, sym::Symbol, commit::AbstractString) = cd(Entry.tag,pkg,sym,false,commit)

tag(pkg::AbstractString, ver::VersionNumber; force::Bool=false) = cd(Entry.tag,pkg,ver,force)
tag(pkg::AbstractString, ver::VersionNumber, commit::AbstractString; force::Bool=false) =
    cd(Entry.tag,pkg,ver,force,commit)

submit(pkg::AbstractString) = cd(Entry.submit, pkg)
submit(pkg::AbstractString, commit::AbstractString) = cd(Entry.submit,pkg,commit)

"""
    publish()

For each new package version tagged in `METADATA` not already published, make sure that the tagged package commits have been pushed to the repo at the registered URL for the package and if they all have, open a pull request to `METADATA`.
"""
publish() = Entry.publish(Pkg.Dir.getmetabranch())

doc"""
    generate(pkg,license)

Generate a new package named `pkg` with one of these license keys: `"MIT"`, `"BSD"` or `"ASL"`. If you want to make a package with a different license, you can edit it afterwards. Generate creates a git repo at `Pkg.dir(pkg)` for the package and inside it `LICENSE.md`, `README.md`, `REQUIRE`, the julia entrypoint `$pkg/src/$pkg.jl`, and Travis and AppVeyor CI configuration files `.travis.yml` and `appveyor.yml`.
"""
generate(pkg::AbstractString, license::AbstractString;
         force::Bool=false, authors::Union{AbstractString,Array} = [], config::Dict=Dict()) =
    cd(Generate.package, pkg, license, force=force, authors=authors, config=config)


end # module
