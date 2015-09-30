module PkgDev

export Entry, Generate,
       register, tag, submit, publish, generate

include("entry.jl")
include("generate.jl")

const cd = Pkg.Dir.cd

register(pkg::AbstractString) = cd(Entry.register,pkg)
register(pkg::AbstractString, url::AbstractString) = cd(Entry.register,pkg,url)

tag(pkg::AbstractString, sym::Symbol=:patch) = cd(Entry.tag,pkg,sym)
tag(pkg::AbstractString, sym::Symbol, commit::AbstractString) = cd(Entry.tag,pkg,sym,false,commit)

tag(pkg::AbstractString, ver::VersionNumber; force::Bool=false) = cd(Entry.tag,pkg,ver,force)
tag(pkg::AbstractString, ver::VersionNumber, commit::AbstractString; force::Bool=false) =
    cd(Entry.tag,pkg,ver,force,commit)

submit(pkg::AbstractString) = cd(Entry.submit, pkg)
submit(pkg::AbstractString, commit::AbstractString) = cd(Entry.submit,pkg,commit)

publish() = cd(Entry.publish,Dir.getmetabranch())

generate(pkg::AbstractString, license::AbstractString; force::Bool=false, authors::Union{AbstractString,Array} = [], config::Dict=Dict()) =
    cd(Generate.package,pkg,license,force=force,authors=authors,config=config)


end # module
