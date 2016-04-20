"Search for all dependencies of specified package."
function deps(pkg::AbstractString, pkgreqs, all_avail, res::Dict{AbstractString,VersionNumber})
    for (dep, depvset) in pkgreqs
        dep == "julia" && continue
        haskey(res, dep) && continue
        depvers = all_avail[dep]
        supported = filter(vp->vp[2], map(v->(v,in(v,depvset)), sort(collect(keys(depvers)), rev=true)))
        length(supported) == 0 && error("No supported versions of $dep")
        depver = supported[1][1]
        res[dep] = depver
        deps(dep, all_avail[dep][depver].requires, all_avail, res)
    end
    return res
end

"""Bundle package with its dependencies

Returns map of packages and their locations for the provided package and its dependencies
"""
function bundle(pkg::AbstractString="")
    pkgdir = PkgDev.dir(pkg)
    pkgreqfile = joinpath(pkgdir, "REQUIRE")
    isfile(pkgreqfile) || error("Package $pkg does not have REQUIRE file")
    pkgreqs = Pkg.Reqs.parse(pkgreqfile)
    all_avail = Pkg.cd(Pkg.Read.available)

    bundle = Dict{AbstractString,AbstractString}()
    # println("Bundle for $pkg: $pkgdir")
    bundle[pkg] = pkgdir
    for (pkgdep, depver) in deps(pkg, pkgreqs, all_avail, Dict{AbstractString,VersionNumber}())
        bundle[pkgdep] = PkgDev.dir(pkgdep)
        # println("\t$pkgdep [$depver]: $(bundle[pkgdep])")
    end
    return bundle
end

