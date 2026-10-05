sub init()
    m.top.functionName = "doFetch"
end sub

sub doFetch()
    req = CreateObject("roUrlTransfer")
    url = m.top.url
    sep = "?"
    if Instr(1, url, "?") > 0 then sep = "&"
    req.SetUrl(url + sep + "_t=" + CreateObject("roDateTime").AsSeconds().ToStr())
    req.SetCertificatesFile("common:/certs/ca-bundle.crt")
    req.InitClientCertificates()
    req.EnableEncodings(true)
    body = req.GetToString()
    if body = "" then
        m.top.error = "Sem resposta do servidor"
        return
    end if
    json = ParseJson(body)
    if json = invalid then
        m.top.error = "JSON invalido"
        return
    end if
    if type(json) = "roArray" then json = { cams: json }
    m.top.result = json
end sub
