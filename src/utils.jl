import URIParser

function getrepohttpurl(reporemoteurl::AbstractString)
    repouri = URIParser.URI(reporemoteurl)
    repopath = splitext(repouri.path)[1] # remove git suffix
    repourl = URIParser.URI("https", repouri.host, repouri.port, repopath)
    string(repourl)
end
