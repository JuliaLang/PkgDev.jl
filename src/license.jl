const LICENSES = Dict(
    "MIT" => "MIT \"Expat\" License",
    "BSD" => "Simplified \"2-clause\" BSD License",
    "ISC" => "Internet Systems Consortium Licence",
    "ASL" => "Apache License, Version 2.0",
    "MPL" => "Mozilla Public License, Version 2.0",
    "GPL-2.0+" => "GNU Public License, Version 2.0+",
    "GPL-3.0+" => "GNU Public License, Version 3.0+",
    "LGPL-2.1+" => "Lesser GNU Public License, Version 2.1+",
    "LGPL-3.0+" => "Lesser GNU Public License, Version 3.0+",
    "CC0" => "Creative Commons Universal Public Domain Dedication (CC0 1.0)"
)


"Read license text from specified file and location"
function readlicense(lic::AbstractString,
                     dir::AbstractString=normpath(@__DIR__, "..", "res", "licenses"))
    return read(joinpath(dir, lic), String)
end

"""
    license([name])

Shows available licenses if no parameters specified. If a license name is specified as a parameter then the function shows the license text.
"""
function license(lic::AbstractString="")
    if isempty(lic)
        lics =""
        for k in LICENSES |> keys |> collect |> sort
            lics *= " $k | $(LICENSES[k])\n"
        end
        maxdesclen = maximum(map(length,values(LICENSES)))
        lics = "Label| Full name\n-----|$(repeat("-", maxdesclen+2))\n$lics"
        println(lics)
        # Base.Markdown.term(STDOUT, lics)
    else
        try
            println(readlicense(lic))
        catch
            printstyled("License $lic is not available.", color=:red)
        end
    end
end
